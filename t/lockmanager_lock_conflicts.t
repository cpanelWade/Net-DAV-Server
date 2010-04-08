#!/usr/bin/perl

use Test::More tests => 12;
use Carp;

use strict;
use warnings;

use Net::DAV::LockManager ();
use Net::DAV::LockManager::Simple ();

my $token_re = qr/^opaquelocktoken:[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/;

{
    my $label = 'Beneath lock';
    my $db = Net::DAV::LockManager::Simple->new();
    my $mgr = Net::DAV::LockManager->new($db);
    my $token = $mgr->lock({ 'path' => '/foo', 'owner' => 'fred' })->token;
    like( $token, $token_re, "$label: Initial lock" );
    ok( !defined $mgr->lock({ 'path' => '/foo/bar/baz', 'owner' => 'bianca' }), "$label: non-owner cannot lock without token" );
    ok( !defined $mgr->lock({ 'path' => '/foo/bar/baz', 'owner' => 'fred' }), "$label: owner cannot lock without token" );

    ok( !defined $mgr->lock({ 'path' => '/foo/bar/baz', 'owner' => 'bianca', 'token' => $token }), "$label: non-owner cannot lock with token" );
    my $token2 = $mgr->lock({ 'path' => '/foo/bar/baz', 'owner' => 'fred', 'token' => $token })->token;
    like( $token2, $token_re, "$label: owner can lock with token" );
    isnt( $token2, $token, "$label: tokens are not the same." );
}

{
    my $label = 'Lock ancestor';
    my $db = Net::DAV::LockManager::Simple->new();
    my $mgr = Net::DAV::LockManager->new($db);
    my $token = $mgr->lock({ 'path' => '/foo/bar/baz', 'owner' => 'fred' })->token;
    like( $token, $token_re, "$label: Initial lock" );
    ok( !defined $mgr->lock({ 'path' => '/foo', 'owner' => 'bianca' }), "$label: non-owner cannot lock without token" );
    ok( !defined $mgr->lock({ 'path' => '/foo', 'owner' => 'fred' }), "$label: owner cannot lock without token" );

    ok( !defined $mgr->lock({ 'path' => '/foo', 'owner' => 'bianca', 'token' => $token }), "$label: non-owner cannot lock with token" );
    my $token2 = $mgr->lock({ 'path' => '/foo', 'owner' => 'fred', 'token' => $token })->token;
    like( $token2, $token_re, "$label: owner can lock with token" );
    isnt( $token2, $token, "$label: tokens are not the same." );
}


