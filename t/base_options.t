#!/usr/bin/perl

use Test::More 'no_plan'; #tests => 1;
use Carp;

use strict;
use warnings;

{
    package Mock::FileSystem::Locking;
    sub new { return bless {}; }
    sub lock {}
    sub unlock {}
}

{
    package Mock::FileSystem::NonLocking;
    sub new { return bless {}; }
}

use Net::DAV::Server ();

{
    my $dav = Net::DAV::Server->new();
    my $res = $dav->options( HTTP::Request->new(), HTTP::Response->new( 200 ) );
    isa_ok( $res, 'HTTP::Response' );
    is( $res->header('MS-Author-Via'), 'DAV', 'No FS: Microsoft author header' );
    TODO: {
        local $TODO = 'Locking should not be reported for missing filesys.';
        is( $res->header( 'DAV' ), '1,<http://apache.org/dav/propset/fs/1>', 'No FS: Capability header is correct.' );
        is_deeply(
            [ sort split /,\s*/, $res->header('Allow') ],
            [ qw/COPY DELETE GET HEAD MKCOL MOVE OPTIONS POST PROPFIND PUT/ ],
            'No FS: Expected methods are allowed.'
        );
    }
}

{
    my $dav = Net::DAV::Server->new();
    $dav->filesys( Mock::FileSystem::NonLocking->new() );
    my $res = $dav->options( HTTP::Request->new(), HTTP::Response->new( 200 ) );
    isa_ok( $res, 'HTTP::Response' );
    is( $res->header('MS-Author-Via'), 'DAV', 'Non-Locking FS: Microsoft author header' );
    TODO: {
        local $TODO = 'Locking should not be reported for filesys with no locking.';
        is( $res->header( 'DAV' ), '1,<http://apache.org/dav/propset/fs/1>', 'Non-Locking FS: Capability header is correct.' );
        is_deeply(
            [ sort split /,\s*/, $res->header('Allow') ],
            [ qw/COPY DELETE GET HEAD MKCOL MOVE OPTIONS POST PROPFIND PUT/ ],
            'Non-Locking FS: Expected methods are allowed.'
        );
    }
}

{
    my $dav = Net::DAV::Server->new();
    $dav->filesys( Mock::FileSystem::Locking->new() );
    my $res = $dav->options( HTTP::Request->new(), HTTP::Response->new( 200 ) );
    isa_ok( $res, 'HTTP::Response' );
    isa_ok( $dav->filesys, 'Mock::FileSystem::Locking' );
    is( $res->header( 'DAV' ), '1,2,<http://apache.org/dav/propset/fs/1>', 'Locking FS: Capability header is correct.' );
    is( $res->header('MS-Author-Via'), 'DAV', 'Locking FS: Microsoft author header' );
    TODO: {
        local $TODO = 
        is_deeply(
            [ sort split /,\s*/, $res->header('Allow') ],
            [ qw/COPY DELETE GET HEAD LOCK MKCOL MOVE OPTIONS POST PROPFIND PUT UNLOCK/ ],
            'Locking FS: Expected methods are allowed.'
        );
    }
}

