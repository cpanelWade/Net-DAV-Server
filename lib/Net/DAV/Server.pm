package Net::DAV::Server;
use strict;
use warnings;
use DateTime;
use DateTime::Format::HTTP;
use File::Slurp;
use HTTP::Date;
use HTTP::Headers;
use HTTP::Response;
use HTTP::Request;
use URI;
use URI::Escape;
use base 'Class::Accessor::Fast';
__PACKAGE__->mk_accessors(qw(filesys));
our $VERSION = '1.21';

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

  my $response;
  if ($method eq 'OPTIONS') {
    my $headers = HTTP::Headers->new(
      'Date'          => time2str(time),
      'Server'        => 'Foomatic',
      'Content-Type'  => 'text/plain',
      'DAV'           => 1,
      'Allow'         =>
'OPTIONS, GET, HEAD, POST, DELETE, TRACE, PROPFIND, PROPPATCH, COPY, MOVE, LOCK, UNLOCK',
      'Connection' => 'close',
    );
    $response = HTTP::Response->new(200, "OK", $headers);
  } elsif ($method eq 'GET') {
    my $path  = uri_unescape($request->uri);
    my $headers = HTTP::Headers->new(
      'Date'          => time2str(time),
      'Server'        => 'Foomatic',
      'Content-Type'  => 'text/plain',
      'Connection'    => 'close',
    );
    if ($fs->test("f", $path) && $fs->test("r", $path)) {
      $response = HTTP::Response->new(200, "OK", $headers);

      my $fh = $fs->open_read($path);
      my $file = join '', <$fh>;
      $fs->close_read($fh);
      $response->content($file);
    } elsif ($fs->test("d", $path)) {
      # a web browser, then
      $response = HTTP::Response->new(200, "OK", $headers);
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
      $response = HTTP::Response->new(404, "NOT FOUND", $headers);
    }
  } elsif ($method eq 'PUT') {
    my $path    = $request->uri;
    my $headers = HTTP::Headers->new(
      'Date'          => time2str(time),
      'Server'        => 'Foomatic',
      'Content-Type'  => 'text/plain',
      'Connection'    => 'close',
    );

    #  if ($fs->test("f", $path) && $fs->test("r", $path)) {
    $response = HTTP::Response->new(201, "CREATED", $headers);

    my $fh = $fs->open_write($path);
    print $fh $request->content;
    $fs->close_write($fh);

    #  } else {
    #    $response = HTTP::Response->new(404, "NOT FOUND", $headers );
    #  }
  } elsif ($method eq 'DELETE') {
    my $path    = $request->uri;
    my $headers = HTTP::Headers->new(
      'Date'          => time2str(time),
      'Server'        => 'Foomatic',
      'Content-Type'  => 'text/plain',
      'Connection'    => 'close',
    );
    if ($fs->test("f", $path)) {
      $fs->delete($path);
      $response = HTTP::Response->new(200, "OK", $headers);
    } elsif ($fs->test("d", $path)) {
      warn "do not deeply delete collections yet";
      foreach my $f ($fs->list($path)) {
        next if $f =~ /^\.+$/;
        $fs->delete("$path$f") || warn "uhoh";
      }
      $fs->rmdir($path);
      $response = HTTP::Response->new(200, "OK", $headers);
    } else {
      $response = HTTP::Response->new(404, "NOT FOUND", $headers);
    }
  } elsif ($method eq 'COPY') {
    my $path        = $request->uri;
    my $destination = $request->header('Destination');
    $destination = URI->new($destination)->path;
    my $depth     = $request->header('Depth');
    my $overwrite = $request->header('Overwrite');

    my $headers = HTTP::Headers->new(
      'Date'          => time2str(time),
      'Server'        => 'Foomatic',
      'Content-Type'  => 'text/plain',
      'Connection'    => 'close',
    );
    if ($fs->test("f", $path)) {
      if ($fs->test("d", $destination)) {
        $response = HTTP::Response->new(204, "NO CONTENT", $headers);
      } elsif ($fs->test("f", $path) && $fs->test("r", $path)) {
        my $fh = $fs->open_read($path);
        my $file = join '', <$fh>;
        $fs->close_read($fh);
        if ($fs->test("f", $destination)) {
          if ($overwrite eq 'T') {
            $fh = $fs->open_write($destination);
            print $fh $request->content;
            $fs->close_write($fh);
            $response = HTTP::Response->new(200, "OK", $headers);
          } else {
            $response =
              HTTP::Response->new(412, "PRECONDITION FAILED", $headers);
          }
        } else {
          $fh = $fs->open_write($destination);
          print $fh $request->content;
          $fs->close_write($fh);
          $response = HTTP::Response->new(201, "CREATED", $headers);
        }
      } else {
        $response = HTTP::Response->new(404, "NOT FOUND", $headers);
      }
    } else {
      warn "do not copy dirs yet";
    }
  } elsif ($method eq 'MKCOL') {
    my $path    = $request->uri;
    my $headers = HTTP::Headers->new(
      'Date'          => time2str(time),
      'Server'        => 'Foomatic',
      'Content-Type'  => 'text/plain',
      'Connection'    => 'close',
    );
    if ($request->content) {
      $response = HTTP::Response->new(415, "UNSUPPORTED MEDIA TYPE", $headers);
    } elsif (not $fs->test("e", $path)) {
      $fs->mkdir($path);
      if ($fs->test("d", $path)) {
        $response = HTTP::Response->new(200, "OK", $headers);
      } else {
        $response = HTTP::Response->new(409, "CONFLICT", $headers);
      }
    } else {
      $response = HTTP::Response->new(405, "NOT ALLOWED", $headers);
    }
  } elsif ($method eq 'PROPFIND') {
    my $path  = uri_unescape($request->uri);
    my $depth = $request->header('Depth');
#    warn "(depth $depth for $path)\n";
    my $headers = HTTP::Headers->new(
      'Date'          => time2str(time),
      'Server'        => 'Foomatic',
      'Content-Type'  => 'text/xml; charset="utf-8"',
      'Connection'    => 'close',
    );
    $response = HTTP::Response->new(207, "Multi-Status", $headers);
    my $content = q|<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">|;

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

      my ($resourcetype, $contenttype, $status);

      my (
        $dev,  $ino,   $mode,  $nlink, $uid,     $gid, $rdev,
        $size, $atime, $mtime, $ctime, $blksize, $blocks
        )
        = $fs->stat($file);
      my $mtime_dt = DateTime->from_epoch(epoch => $mtime || 0);
      $mtime = DateTime::Format::HTTP->format_datetime($mtime_dt);

      $size ||= "";

      if ($fs->test("d", $file)) {
        $resourcetype = '<D:collection/>';
        $contenttype  = 'httpd/unix-directory';
        $status       = "HTTP/1.1 200 OK";
      } elsif ($fs->test("f", $file)) {
        $resourcetype = '';
        $contenttype  = 'httpd/unix-file';
        $status       = "HTTP/1.1 200 OK";
      } else {
        $resourcetype = '';
        $contenttype  = '';
        $status       = "HTTP/1.1 404 NOT FOUND";
      }

      $file =~ s/&/&amp;/g;

      $content .= qq|
<D:response xmlns:lp0="DAV:" xmlns:lp1="http://apache.org/dav/props/">
<D:href>$file</D:href>
<D:propstat>
<D:prop>
<lp0:creationdate xmlns:b="urn:uuid:c2f41010-65b3-11d1-a29f-00aa00c14882/" b:dt="dateTime.tz">$mtime_dt</lp0:creationdate>
<lp0:getlastmodified xmlns:b="urn:uuid:c2f41010-65b3-11d1-a29f-00aa00c14882/" b:dt="dateTime.rfc1123">$mtime</lp0:getlastmodified>
<D:getcontentlength>$size</D:getcontentlength>
<D:supportedlock/>
<D:lockdiscovery/>
<D:resourcetype>$resourcetype</D:resourcetype>
<D:getcontenttype>$contenttype</D:getcontenttype>
</D:prop>
<D:status>$status</D:status>
</D:propstat>
</D:response>|;

    }

    $content .= "</D:multistatus>";
    $response->content($content);
  } else {
    die "unknown request method $method ";
  }

  $response->header('Content-Length' => length($response->content));
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
