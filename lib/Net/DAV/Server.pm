package Net::DAV::Server;
use strict;
use warnings;
use File::Slurp;
use Encode qw(encode_utf8);
use File::Find::Rule::Filesys::Virtual;
use HTTP::Date;
use HTTP::Headers;
use HTTP::Response;
use HTTP::Request;
use URI;
use URI::Escape;
use XML::LibXML;
use base 'Class::Accessor::Fast';
__PACKAGE__->mk_accessors(qw(filesys));
our $VERSION = '1.23';

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
'OPTIONS, GET, HEAD, POST, DELETE, TRACE, PROPFIND, PROPPATCH, COPY, MOVE');
  return $response;
}

sub proppatch {
  my($self, $request, $response) = @_;
  $response = HTTP::Response->new(403, "FORBIDDEN", $response->headers);
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

  unless ($fs->test("e", $path)) {
    return HTTP::Response->new(404, "NOT FOUND", $response->headers);
  }

  my @files =
    map { s{/+}{/}g; $_ } 
    File::Find::Rule::Filesys::Virtual
   ->virtual($fs)
   ->file
   ->in($path);

  my @dirs = reverse sort
    grep { $_ !~ m{/\.\.?$} }
    map { s{/+}{/}g; $_ } 
    File::Find::Rule::Filesys::Virtual
   ->virtual($fs)
   ->directory
   ->in($path);

  foreach my $file (@files) {
    $fs->delete($file);
  }

  foreach my $dir (@dirs) {
    $fs->rmdir($dir);
  }

  if ($fs->test("d", $path)) {
    $fs->rmdir($path);
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
    return $self->copy_file($request, $response);
  }

  # it's a good approximation
  $depth = 100 if $depth eq 'infinity';

  my @files =
    map { s{/+}{/}g; $_ } 
    File::Find::Rule::Filesys::Virtual
   ->virtual($fs)
   ->file
   ->maxdepth($depth)
   ->in($path);

  my @dirs = reverse sort
    grep { $_ !~ m{/\.\.?$} }
    map { s{/+}{/}g; $_ } 
    File::Find::Rule::Filesys::Virtual
   ->virtual($fs)
   ->directory
   ->maxdepth($depth)
   ->in($path);

  push @dirs, $path;
  foreach my $dir (sort @dirs) {
    my $destdir = $dir;
    $destdir =~ s/^$path/$destination/;
    if ($overwrite eq 'F' && $fs->test("e", $destdir)) {
      return HTTP::Response->new(401, "ERROR", $response->headers);
    }
    $fs->mkdir($destdir);
  }

  foreach my $file (reverse sort @files) {
    my $destfile = $file;
    $destfile =~ s/^$path/$destination/;
    my $fh = $fs->open_read($file);
    my $file = join '', <$fh>;
    $fs->close_read($fh);
    if ($fs->test("e", $destfile)) {
      if ($overwrite eq 'T') {
        $fh = $fs->open_write($destfile);
        print $fh $file;
        $fs->close_write($fh);
      } else {
      }
    } else {
      $fh = $fs->open_write($destfile);
      print $fh $file;
      $fs->close_write($fh);
    }
  }

  $response = HTTP::Response->new(200, "OK", $response->headers);
  return $response;
}

sub copy_file {
  my($self, $request, $response) = @_;
  my $path = uri_unescape($request->uri);
  my $fs = $self->filesys;

  my $destination = $request->header('Destination');
  $destination = URI->new($destination)->path;
  my $depth     = $request->header('Depth');
  my $overwrite = $request->header('Overwrite');

  if ($fs->test("d", $destination)) {
    $response = HTTP::Response->new(204, "NO CONTENT", $response->headers);
  } elsif ($fs->test("f", $path) && $fs->test("r", $path)) {
    my $fh = $fs->open_read($path);
    my $file = join '', <$fh>;
    $fs->close_read($fh);
    if ($fs->test("f", $destination)) {
      if ($overwrite eq 'T') {
	$fh = $fs->open_write($destination);
	print $fh $file;
	$fs->close_write($fh);
      } else {
	$response =
	  HTTP::Response->new(412, "PRECONDITION FAILED", $response->headers);
      }
    } else {
      $fh = $fs->open_write($destination);
      print $fh $file;
      $fs->close_write($fh);
      $response = HTTP::Response->new(201, "CREATED", $response->headers);
    }
  } else {
    $response = HTTP::Response->new(404, "NOT FOUND", $response->headers);
  }
  return $response;
}

sub move {
  my($self, $request, $response) = @_;
  $response = $self->copy($request, $response);
  $response = $self->delete($request, $response);
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

  if ($request->headers->header('Content-Length')) {
    my $content = $request->content;
    my $p = XML::LibXML->new;
    eval {
      my $doc = $p->parse_string($content);
    };
    if ($@) {
      return HTTP::Response->new(400, "BAD REQUEST", $response->headers);
    }
    return HTTP::Response->new(403, "FORBIDDEN", $response->headers);
  }

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
