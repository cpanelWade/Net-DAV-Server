#!/usr/bin/perl

use Test::More 'no_plan'; #tests => 1;
use Carp;

use strict;
use warnings;

use Net::DAV::Server ();
use Net::DAV::LockManager::Simple ();
use XML::LibXML;
use XML::LibXML::XPathContext;
use Data::Dumper;

my $parser = XML::LibXML->new();

{
    package Mock::Filesys;
    sub new {
        return bless {
            '/' =>               [ 0, 0, 01777, 2, 1, 1, 0,    0, (time)x3, 1024, 1 ],
            '/foo' =>            [ 0, 0, 01777, 2, 1, 1, 0,    0, (time)x3, 1024, 1 ],
            '/foo/bar' =>        [ 0, 0, 01777, 2, 1, 1, 0,    0, (time)x3, 1024, 1 ],
            '/test.html' =>      [ 0, 0, 0666,  1, 1, 1, 0, 1024, (time)x3, 1024, 1 ],
            '/foo/index.html' => [ 0, 0, 0666,  1, 1, 1, 0, 2048, (time)x3, 1024, 2 ],
            '/bar' =>            [ 0, 0, 01777, 2, 1, 1, 0,    0, (time)x3, 1024, 1 ],
        };
    }
    sub test {
        my ($self, $op, $path) = @_;

        if ( $op eq 'e' ) {
            return exists $self->{$path};
        }
        elsif ( $op eq 'd' ) {
            return unless exists $self->{$path};
            return (($self->{$path}->[2]&01000) ? 1 : 0);
        }
        else {
            die "Operation $op not implemented.";
        }
    }
    sub stat {
        my ($self, $path) = @_;

        return unless exists $self->{$path};
        return @{$self->{$path}};
    }
}

{
    my $label = 'Missing item';
    my $dav = Net::DAV::Server->new( -filesys => Mock::Filesys->new(), -dbobj => Net::DAV::LockManager::Simple->new() );
    my $fs = $dav->filesys;

    ok( !$fs->test( 'e', '/fred' ), "$label: target does not initially exist" );
    my $req = HTTP::Request->new( PROPFIND => '/fred' );
    $req->authorization_basic( 'fred', 'fredmobile' );

    my $resp = $dav->propfind( $req, HTTP::Response->new( 200, 'OK' ) );
    is( $resp->code, 404, "$label: Response is 'Not Found'" );
}

{
    my $label = 'Depth 1 dir, default';
    my $dav = Net::DAV::Server->new( -filesys => Mock::Filesys->new(), -dbobj => Net::DAV::LockManager::Simple->new() );
    my $fs = $dav->filesys;

    ok( $fs->test( 'e', '/' ), "$label: root directory exists" );
    my $req = HTTP::Request->new( PROPFIND => '/' );
    $req->authorization_basic( 'fred', 'fredmobile' );

    my $resp = $dav->propfind( $req, HTTP::Response->new( 200, 'OK' ) );
    is( $resp->code, 207, "$label: Response is 'Multi-Status'" );
    my $xpc = get_xml_context( $resp->content );
    has_text( $xpc, '/D:multistatus/D:response/D:href', '/', "$label: Path is correct" );
    has_nodes( $xpc,
        '/D:multistatus/D:response/D:propstat/D:prop[1]',
        [ qw/creationdate getcontentlength getcontenttype getlastmodified supportedlock resourcetype/ ],
        "$label: Property nodes"
    );
    has_node( $xpc,
        '/D:multistatus/D:response/D:propstat/D:prop/D:supportedlock/D:lockentry/D:lockscope',
        'exclusive',
        "$label: supported scopes"
    );
}

{
    my $label = 'File, default';
    my $dav = Net::DAV::Server->new( -filesys => Mock::Filesys->new(), -dbobj => Net::DAV::LockManager::Simple->new() );
    my $fs = $dav->filesys;

    ok( $fs->test( 'e', '/test.html' ), "$label: file exists" );
    my $req = HTTP::Request->new( PROPFIND => '/test.html' );
    $req->authorization_basic( 'fred', 'fredmobile' );

    my $resp = $dav->propfind( $req, HTTP::Response->new( 200, 'OK' ) );
    is( $resp->code, 207, "$label: Response is 'Multi-Status'" );
    my $xpc = get_xml_context( $resp->content );
    has_text( $xpc, '/D:multistatus/D:response/D:href', '/test.html', "$label: Path is correct" );
    has_nodes( $xpc,
        '/D:multistatus/D:response/D:propstat/D:prop[1]',
        [ qw/creationdate getcontentlength getcontenttype getlastmodified supportedlock resourcetype/ ],
        "$label: Property nodes"
    );
    has_node( $xpc,
        '/D:multistatus/D:response/D:propstat/D:prop/D:supportedlock/D:lockentry/D:lockscope',
        'exclusive',
        "$label: supported scopes"
    );
}

{
    my $label = 'Depth 1 dir, allprop';
    my $dav = Net::DAV::Server->new( -filesys => Mock::Filesys->new(), -dbobj => Net::DAV::LockManager::Simple->new() );
    my $fs = $dav->filesys;

    ok( $fs->test( 'e', '/' ), "$label: root directory exists" );
    my $req = HTTP::Request->new( PROPFIND => '/' );
    $req->content( '<D:propfind xmlns:D="DAV:"><D:allprop/></D:propfind>' );
    $req->header( 'Content-Length', length $req->content );
    $req->authorization_basic( 'fred', 'fredmobile' );

    my $resp = $dav->propfind( $req, HTTP::Response->new( 200, 'OK' ) );
    is( $resp->code, 207, "$label: Response is 'Multi-Status'" );
    my $xpc = get_xml_context( $resp->content );
    has_text( $xpc, '/D:multistatus/D:response/D:href', '/', "$label: Path is correct" );
    has_nodes( $xpc,
        '/D:multistatus/D:response/D:propstat/D:prop[1]',
        [ qw/creationdate getcontentlength getcontenttype getlastmodified supportedlock resourcetype/ ],
        "$label: Property nodes"
    );
    has_node( $xpc,
        '/D:multistatus/D:response/D:propstat/D:prop/D:supportedlock/D:lockentry/D:lockscope',
        'exclusive',
        "$label: supported scopes"
    );
}

{
    my $label = 'File, allprop';
    my $dav = Net::DAV::Server->new( -filesys => Mock::Filesys->new(), -dbobj => Net::DAV::LockManager::Simple->new() );
    my $fs = $dav->filesys;

    ok( $fs->test( 'e', '/test.html' ), "$label: file exists" );
    my $req = HTTP::Request->new( PROPFIND => '/test.html' );
    $req->content( '<D:propfind xmlns:D="DAV:"><D:allprop/></D:propfind>' );
    $req->header( 'Content-Length', length $req->content );
    $req->authorization_basic( 'fred', 'fredmobile' );

    my $resp = $dav->propfind( $req, HTTP::Response->new( 200, 'OK' ) );
    is( $resp->code, 207, "$label: Response is 'Multi-Status'" );
    my $xpc = get_xml_context( $resp->content );
    has_text( $xpc, '/D:multistatus/D:response/D:href', '/test.html', "$label: Path is correct" );
    has_nodes( $xpc,
        '/D:multistatus/D:response/D:propstat/D:prop[1]',
        [ qw/creationdate getcontentlength getcontenttype getlastmodified supportedlock resourcetype/ ],
        "$label: Property nodes"
    );
    has_node( $xpc,
        '/D:multistatus/D:response/D:propstat/D:prop/D:supportedlock/D:lockentry/D:lockscope',
        'exclusive',
        "$label: supported scopes"
    );
}

sub get_xml_context {
    my ($content) = @_;
    my $doc = eval { $parser->parse_string( $content ) };
    die "Unable to parse content.\n" unless defined $doc;
    my $xpc = XML::LibXML::XPathContext->new( $doc );
    $xpc->registerNs( 'D', 'DAV:' );
    return $xpc;
}

sub has_text {
    my ($xpc, $xpath, $expect, $label) = @_;
    my @nodes = $xpc->findnodes( "$xpath/text()" );
    is( $nodes[0]->data, $expect, $label );
}

sub has_texts {
    my ($xpc, $xpath, $expect, $label) = @_;
    my @nodes = map { $_->data } $xpc->findnodes( "$xpath/text()" );
    is_deeply( \@nodes, $expect, $label );
}

sub has_nodes {
    my ($xpc, $xpath, $tags, $label) = @_;
    my @nodes = map { $_->localname } $xpc->findnodes( "$xpath/D:*" );
    is_deeply( \@nodes, $tags, $label );
}

sub has_node {
    my ($xpc, $xpath, $tag, $label) = @_;
    my @nodes = map { $_->localname } $xpc->findnodes( "$xpath/D:*" );
    is( $nodes[0], $tag, $label );
}
