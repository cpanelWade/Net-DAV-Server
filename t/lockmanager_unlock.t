#!/usr/bin/perl

use Test::More tests => 8;
use Carp;

use strict;
use warnings;

use Net::DAV::LockManager ();
use Net::DAV::UUID ();

# Exploits an implementation detail
my $mock_token = 'opaquelocktoken:' . Net::DAV::UUID::generate( '/tmp/file', 'fred' );

{
    my $mgr = Net::DAV::LockManager->new();

    ok( !$mgr->unlock({ 'path' => '/tmp/file', 'owner' => 'fred', 'token' => $mock_token }),
        'Can not unlock a non-existent lock' );
}

{
    my $mgr = Net::DAV::LockManager->new();
    my $lck = $mgr->lock({ 'path' => '/tmp/file', 'owner' => 'bianca' });

    ok( !$mgr->unlock({ 'path' => '/tmp/file', 'owner' => 'fred', 'token' => $lck->{'token'} }),
        'Can not unlock non-owned lock' );
}

{
    my $mgr = Net::DAV::LockManager->new();
    my $lck = $mgr->lock({ 'path' => '/tmp', 'owner' => 'fred' });

    ok( !$mgr->unlock({ 'path' => '/tmp/file', 'owner' => 'fred', 'token' => $lck->{'token'} }),
        'Can not unlock ancestor lock' );
}

{
    my $mgr = Net::DAV::LockManager->new();
    my $lck = $mgr->lock({ 'path' => '/tmp/file1', 'owner' => 'fred' });

    ok( !$mgr->unlock({ 'path' => '/tmp/file', 'owner' => 'fred', 'token' => $lck->{'token'} }),
        'Can not unlock sibling lock' );
}

{
    my $mgr = Net::DAV::LockManager->new();
    my $lck = $mgr->lock({ 'path' => '/tmp/file', 'owner' => 'fred' });

    ok( !$mgr->unlock({ 'path' => '/tmp/file', 'owner' => 'fred', 'token' => $mock_token }),
        'Can not unlock with wrong token' );
}

{
    my $mgr = Net::DAV::LockManager->new();
    my $lck = $mgr->lock({ 'path' => '/tmp/file', 'owner' => 'fred' });
    ok( !$mgr->can_modify({ 'path' => '/tmp/file', 'owner' => 'bianca' }), 'Can not modify locked resource.' );

    ok( $mgr->unlock({ 'path' => '/tmp/file', 'owner' => 'fred', 'token' => $lck->{'token'} }),
        'Successfully unlocked resource' );
    ok( $mgr->can_modify({ 'path' => '/tmp/file', 'owner' => 'bianca' }), 'Can modify unlocked resource.' );
}

