package Net::DAV::Server;
use strict;
use warnings;
use File::Slurp;
use Encode qw(encode_utf8);
use HTTP::Date;
use HTTP::Headers;
use HTTP::Response;
use HTTP::Request;
use URI;
use URI::Escape;
use XML::LibXML;
use base 'Class::Accessor::Fast';
__PACKAGE__->mk_accessors(qw(filesys));
our $VERSION = '1.22';

sub new {
  my ($class) = @_;
  my $self = {};
  bless $self, $class;
  return $self;
}

sub run {
  my $self    = shift;
  my $request = shift;

  my $fs = $self->filesys || die "Boom";

  my $method = $request->method;
  my $path  = uri_unescape($request->uri);

  my $headers = HTTP::Headers->new(
    'Date'         => time2str(time),
    'Server'       => 'Net::DAV::Server ' . $VERSION,
    'Content-Type' => 'text/plain',
    'Connection'   => 'close',
  );
  my $response = HTTP::Response->new(200, "OK", $headers);

  $method = lc $method;
  $response = $self->$method($request, $response);
  $response->header('Content-Length' => length($response->content));
  return $response;
}

sub options {
  my($self, $request, $response) = @_;
  $response->headers->header('DAV' => 1);
  $response->headers->header('Allow' =>
'OPTIONS, GET, HEAD, POST, DELETE, TRACE, PROPFIND, PROPPATCH, COPY, MOVE, LOCK, UNLOCK');
  return $response;
}

sub get {
  my($self, $request, $response) = @_;
  my $path = uri_unescape($request->uri);
  my $fs = $self->filesys;

  if ($fs->test("f", $path) && $fs->test("r", $path)) {
    my $fh = $fs->open_read($path);
    my $file = join '', <$fh>;
    $fs->close_read($fh);
    $response->content($file);
    $response->last_modified($fs->modtime($path)); 
  } elsif ($fs->test("d", $path)) {
    # a web browser, then
    my @files = $fs->list($path);
    my $body;
    foreach my $file (@files) {
      if ($fs->test("d", "$path$file")) {
	$body .= qq|<a href="$file/">$file/</a><br>\n|;
      } else {
	$file =~ s{/$}{};
	$body .= qq|<a href="$file">$file</a><br>\n|;
      }
    }
    $response->header('Content-Type', 'text/html');
    $response->content($body);
  } else {
    $response = HTTP::Response->new(404, "NOT FOUND", $response->headers);
  }
  return $response;
}

sub put {
  my($self, $request, $response) = @_;
  my $path = uri_unescape($request->uri);
  my $fs = $self->filesys;

  $response = HTTP::Response->new(201, "CREATED", $response->headers);

  my $fh = $fs->open_write($path);
  print $fh $request->content;
  $fs->close_write($fh);

  return $response;
}

sub delete {
  my($self, $request, $response) = @_;
  my $path = uri_unescape($request->uri);
  my $fs = $self->filesys;

  if ($fs->test("f", $path)) {
    $fs->delete($path);
  } elsif ($fs->test("d", $path)) {
    warn "do not deeply delete collections yet";
    foreach my $f ($fs->list($path)) {
      next if $f =~ /^\.+$/;
      $fs->delete("$path$f") || warn "uhoh";
    }
    $fs->rmdir($path);
  } else {
    $response = HTTP::Response->new(404, "NOT FOUND", $response->headers);
  }
  return $response;

}

sub copy {
  my($self, $request, $response) = @_;
  my $path = uri_unescape($request->uri);
  my $fs = $self->filesys;

  my $destination = $request->header('Destination');
  $destination = URI->new($destination)->path;
  my $depth     = $request->header('Depth');
  my $overwrite = $request->header('Overwrite');

  if ($fs->test("f", $path)) {
    if ($fs->test("d", $destination)) {
      $response = HTTP::Response->new(204, "NO CONTENT", $response->headers);
    } elsif ($fs->test("f", $path) && $fs->test("r", $path)) {
      my $fh = $fs->open_read($path);
      my $file = join '', <$fh>;
      $fs->close_read($fh);
      if ($fs->test("f", $destination)) {
	if ($overwrite eq 'T') {
	  $fh = $fs->open_write($destination);
	  print $fh $request->content;
	  $fs->close_write($fh);
	} else {
	  $response =
	    HTTP::Response->new(412, "PRECONDITION FAILED", $response->headers);
	}
      } else {
	$fh = $fs->open_write($destination);
	print $fh $request->content;
	$fs->close_write($fh);
	$response = HTTP::Response->new(201, "CREATED", $response->headers);
      }
    } else {
      $response = HTTP::Response->new(404, "NOT FOUND", $response->headers);
    }
  } else {
    warn "do not copy dirs yet";
  }
  return $response;
}

sub mkcol {
  my($self, $request, $response) = @_;
  my $path = uri_unescape($request->uri);
  my $fs = $self->filesys;

  if ($request->content) {
    $response = HTTP::Response->new(415, "UNSUPPORTED MEDIA TYPE", $response->headers);
  } elsif (not $fs->test("e", $path)) {
    $fs->mkdir($path);
    if ($fs->test("d", $path)) {
    } else {
      $response = HTTP::Response->new(409, "CONFLICT", $response->headers);
    }
  } else {
    $response = HTTP::Response->new(405, "NOT ALLOWED", $response->headers);
  }
  return $response;
}

sub propfind {
  my($self, $request, $response) = @_;
  my $path = uri_unescape($request->uri);
  my $fs = $self->filesys;
  my $depth = $request->header('Depth');
  #    warn "(depth $depth for $path)\n";
  $response = HTTP::Response->new(207, "Multi-Status", $response->headers);
  $response->headers->header('Content-Type' => 'text/xml; charset="utf-8"');

  my $dom = XML::LibXML::Document->new("1.0", "utf-8");
  my $multistatus = $dom->createElement("D:multistatus");
  $multistatus->setAttribute("xmlns:D", "DAV:");

  $dom->setDocumentElement($multistatus);

  my @files;
  if ($depth == 1 and $fs->test("d", $path)) {
    my $p = $path;
    $p .= '/' unless $p =~ m{/$};
    @files = map { $p . $_ } $fs->list($path);
    push @files, $path;

    #  print "@files";
  } else {
    @files = ($path);
  }

  foreach my $file (@files) {
    my ($status);

    my (
        $dev,  $ino,   $mode,  $nlink, $uid,     $gid, $rdev,
        $size, $atime, $mtime, $ctime, $blksize, $blocks
       )
      = $fs->stat($file);
    $mtime = time2str($mtime) ;
    $ctime = time2str($ctime);
    $size ||= "";

    if ($fs->test("f", $file)) {
      $status       = "HTTP/1.1 200 OK";
    } elsif ($fs->test("d", $file)) {
      $status       = "HTTP/1.1 200 OK";
    } else {
      $status       = "HTTP/1.1 404 NOT FOUND";
    }

    my $nresponse = $dom->createElement("D:response");
    $nresponse->setAttribute("xmlns:lp0", "DAV:");
    $nresponse->setAttribute("xmlns:lp1", "http://apache.org/dav/props/");
    $multistatus->addChild($nresponse);
    my $href = $dom->createElement("D:href");
    $href->appendText(encode_utf8("$file"));
    $nresponse->addChild($href);
    my $propstat = $dom->createElement("D:propstat");
    $nresponse->addChild($propstat);
    my $prop = $dom->createElement("D:prop");
    $propstat->addChild($prop);
    my $creationdate = $dom->createElement("lp0:creationdate");
    $creationdate->appendText($ctime);
    $prop->addChild($creationdate);
    my $getlastmodified = $dom->createElement("lp0:getlastmodified");
    $getlastmodified->appendText($mtime);
    $prop->addChild($getlastmodified);
    my $getcontentlength = $dom->createElement("D:getcontentlength");
    $getcontentlength->appendText($size);
    $prop->addChild($getcontentlength);
    my $supportedlock = $dom->createElement("D:supportedlock");
    $prop->addChild($supportedlock);
    my $lockdiscovery = $dom->createElement("D:lockdiscovery");
    $prop->addChild($lockdiscovery);
    my $resourcetype = $dom->createElement("D:resourcetype");
    if ($fs->test("d", $file)) {
      my $collection = $dom->createElement("D:collection");
      $resourcetype->addChild($collection);
    }
    $prop->addChild($resourcetype);
    my $nstatus = $dom->createElement("D:status");
    $nstatus->appendText($status);
    $propstat->addChild($nstatus);
    my $getcontenttype = $dom->createElement("D:getcontenttype");

    if ($fs->test("d", $file)) {
      $getcontenttype->appendText("httpd/unix-directory");
    } else {
      $getcontenttype->appendText("httpd/unix-file");
    }

    $propstat->addChild($getcontenttype);
  }

  $response->content($dom->toString(1));

  return $response;
}

1;

__END__

=head1 NAME

Net::DAV::Server - Provide a DAV Server

=head1 SYNOPSIS

  my $filesys = Filesys::Virtual::Plain->new({root_path => $cwd});
  my $webdav = Net::DAV::Server->new();
  $webdav->filesys($filesys);

  my $d = HTTP::Daemon->new(
    LocalAddr => 'localhost',
    LocalPort => 4242,
    ReuseAddr => 1) || die;
  print "Please contact me at: ", $d->url, "\n";
  while (my $c = $d->accept) {
    while (my $request = $c->get_request) {
      my $response = $webdav->run($request);
      $c->send_response ($response);
    }
    $c->close;
    undef($c);
  }

=head1 DESCRIPTION

This module provides a WebDAV server. WebDAV stands for "Web-based
Distributed Authoring and Versioning". It is a set of extensions to
the HTTP protocol which allows users to collaboratively edit and
manage files on remote web servers.

Net::DAV::Server provides a WebDAV server and exports a filesystem for
you using the Filesys::Virtual suite of modules. If you simply want to
export a local filesystem, use Filesys::Virtual::Plain as above.

This module doesn't currently provide a full WebDAV
implementation. However, I am working through the WebDAV server
protocol compliance test suite (litmus, see
http://www.webdav.org/neon/litmus/) and will provide more compliance
in future. The important thing is that it supports cadaver and the Mac
OS X Finder as clients.

=head1 AUTHOR

Leon Brocard <acme@astray.com>

=head1 COPYRIGHT

Copyright (C) 2004, Leon Brocard

This module is free software; you can redistribute it or modify it under
the same terms as Perl itself.
