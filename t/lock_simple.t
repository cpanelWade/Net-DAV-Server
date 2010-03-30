#!/usr/bin/perl

use Test::More 'no_plan'; #tests => 1;
use Carp;

use strict;
use warnings;

use HTTP::Request;
use HTTP::Response;

use Net::DAV::Server;


{
    package Mock::Filesys::Locking;
    sub new {
        return bless {};
    }
    sub lock {
        my ($self, $path) = @_;
        return if $self->{$path};
        $self->{$path} = 1;
        return 1;
    }
    sub unlock {
        my ($self, $path) = @_;
        return unless $self->{$path};
        delete $self->{$path};
        return 1;
    }
}

{
    package Mock::Filesys::NonLocking;
    sub new {
        return bless {};
    }
}

{
    my $dav = Net::DAV::Server->new();
    $dav->filesys( Mock::Filesys::NonLocking->new() );

    my $req = lock_request( '/directory/file', 'Infinite, Second-4100000000', 'exclusive' );
    ok( !defined eval { $dav->lock( $req, HTTP::Response->new( 200 ) ); }, 'lock fails for NonLocking filesystem' );
    $req = unlock_request( '/directory/file', 'token' );
    ok( !defined eval { $dav->unlock( $req, HTTP::Response->new( 200 ) ); }, 'unlock fails for NonLocking filesystem' );
}

{
    my $dav = Net::DAV::Server->new();
    $dav->filesys( Mock::Filesys::Locking->new() );

    my $req = lock_request( '/directory/file', 'Infinite, Second-4100000000', 'exclusive' );
    isa_ok( eval { $dav->lock( $req, HTTP::Response->new( 200 ) ); }, 'HTTP::Response', 'lock succeeds for Locking filesystem' );
    $req = unlock_request( '/directory/file', 'token' );
    isa_ok( eval { $dav->unlock( $req, HTTP::Response->new( 200 ) ); }, 'HTTP::Response', 'unlock succeeds for Locking filesystem' );
}

sub lock_request {
    my ($uri, $timeout, $scope) = @_;
    my $req = HTTP::Request->new( 'LOCK' => $uri, ($timeout?[ 'Timeout' => $timeout ]:()) );
    $scope ||= 'exclusive';
    $req->content( <<"BODY" );
<?xml version="1.0" encoding="utf-8"?>
<D:lockinfo xmlns:D='DAV:'>
    <D:lockscope><D:$scope /></D:lockinfo>
    <D:locktype><D:write/></D:locktype>
    <D:owner>
        <D:href>http://example.org/~gwj/contact.html</D:href>
    </D:owner>
</D:lockinfo>
BODY

    return $req;
}

sub unlock_request {
    my ($uri, $token) = @_;
    return HTTP::Request->new( 'UNLOCK' => $uri, [ 'Lock-Token' => "<$token>" ] );
}

