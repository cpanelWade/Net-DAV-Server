#!/usr/bin/perl

use Test::More 'no_plan'; #tests => 1;
use Carp;

use strict;
use warnings;

use HTTP::Request;
use HTTP::Response;

use Net::DAV::Server ();
use Net::DAV::LockManager::Simple ();

{
    package Mock::Filesys;
    sub new {
        return bless {
            '/' => 'd',
        };
    }
    sub test {
        my ($self, $op, $path) = @_;

        if ( $op eq 'e' ) {
            return exists $self->{$path};
        }
        elsif ( $op eq 'd' ) {
            return exists $self->{$path} and 'd' eq $self->{$path};
        }
        else {
            die "Operation $op not implemented.";
        }
    }
}

{
    my $dav = Net::DAV::Server->new( -filesys => Mock::Filesys->new(), -dbobj => Net::DAV::LockManager::Simple->new() );
    my $req = HTTP::Request->new( POST => '/index.html' );
    $req->authorization_basic( 'fred', 'fredmobile' );

    my $resp = $dav->post( $req, HTTP::Response->new() );
    is( $resp->code, 501, 'POST method not implemented here.' );
}

{
    my $dav = Net::DAV::Server->new( -filesys => Mock::Filesys->new(), -dbobj => Net::DAV::LockManager::Simple->new() );
    my $lresp = $dav->lock( lock_request( '/' ), HTTP::Response->new );
    ok( $lresp && $lresp->code == 200, 'Lock successful' );
    my $req = HTTP::Request->new( POST => '/index.html' );
    $req->authorization_basic( 'bianca', 'fredmobile' );

    my $resp = $dav->post( $req, HTTP::Response->new() );
    is( $resp->code, 403, 'POST blocked by lock.' );
}

sub lock_request {
    my ($uri, $args) = @_;
    my $req = HTTP::Request->new( 'LOCK' => $uri, (exists $args->{timeout}?[ 'Timeout' => $args->{timeout} ]:()) );
    $req->authorization_basic( 'fred', 'fredmobile' );
    if ( $args ) {
        my $scope = $args->{scope} || 'exclusive';
        $req->content( <<"BODY" );
<?xml version="1.0" encoding="utf-8"?>
<D:lockinfo xmlns:D='DAV:'>
    <D:lockscope><D:$scope /></D:lockscope>
    <D:locktype><D:write/></D:locktype>
    <D:owner>
        <D:href>http://fred.org/</D:href>
    </D:owner>
</D:lockinfo>
BODY
    }

    return $req;
}
