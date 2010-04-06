#!/usr/bin/perl

use Test::More 'no_plan'; #tests => 1;
use Carp;

use strict;
use warnings;

use Net::DAV::LockManager ();

my $token_re = qr/^opaquelocktoken:[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/;

# Verify simple locks.
{
    my $mgr = Net::DAV::LockManager->new();
    like( $mgr->lock({ 'path' => '/', 'owner' => 'fred' }), $token_re, 'lock root' );
}

{
    my $mgr = Net::DAV::LockManager->new();
    like( $mgr->lock({ 'path' => '/foo', 'owner' => 'fred' }), $token_re, 'lock one level' );
}

{
    my $mgr = Net::DAV::LockManager->new();
    like( $mgr->lock({ 'path' => '/foo/a/b/c/d/e/f', 'owner' => 'fred' }), $token_re, 'lock multi-level' );
}

# Verify attempted re-lock
{
    my $mgr = Net::DAV::LockManager->new();
    my $token = $mgr->lock({ 'path' => '/foo', 'owner' => 'fred' });
    like( $token, $token_re, 'Initial lock is okay.' );

    ok( !defined $mgr->lock({ 'path' => '/foo', 'owner' => 'fred' }), 'Cannot relock same owner' );
    ok( !defined $mgr->lock({ 'path' => '/foo', 'owner' => 'fred', 'token' => $token }), 'Cannot relock same owner, token' );
    ok( !defined $mgr->lock({ 'path' => '/foo', 'owner' => 'bianca' }), 'Cannot relock different owner' );
}

# Verify nesting locks.
{
    my $mgr = Net::DAV::LockManager->new();
    my $token = $mgr->lock({ 'path' => '/', 'owner' => 'fred' });
    like( $token, $token_re, 'lock root, again' );

    ok( !defined $mgr->lock({ 'path' => '/foo', 'owner' => 'fred' }), 'Cannot lock below an infinite lock' );

    my $ftoken = $mgr->lock({ 'path' => '/foo', 'owner' => 'fred', 'token' => $token });
    like( $ftoken, $token_re, 'Locking with token is allowed' );
    isnt( $token, $ftoken, 'Tokens do not match' );
}

{
    my $mgr = Net::DAV::LockManager->new();
    my $token = $mgr->lock({ 'path' => '/', 'owner' => 'fred' });
    like( $token, $token_re, 'lock root, again' );

    ok( !defined $mgr->lock({ 'path' => '/foo', 'owner' => 'bianca' }), 'Cannot lock with wrong owner and no token' );
    ok( !defined $mgr->lock({ 'path' => '/foo', 'owner' => 'bianca', 'token' => $token }), 'Cannot lock with wrong owner' );
}

# Verify non-overlapping locks
{
    my $mgr = Net::DAV::LockManager->new();
    my $token = $mgr->lock({ 'path' => '/bar', 'owner' => 'fred' });
    like( $token, $token_re, 'fred locks bar' );

    my $otoken = $mgr->lock({ 'path' => '/foo', 'owner' => 'bianca' });
    like( $otoken, $token_re, 'bianca locks foo' );
    isnt( $token, $otoken, 'Non-overlapping tokens do not match' );
}

# Verify nested non-infinity locks.
{
    my $mgr = Net::DAV::LockManager->new();
    my $token = $mgr->lock({ 'path' => '/', 'owner' => 'fred', 'depth' => 0 });
    like( $token, $token_re, 'non-infinity: lock root, again' );

    my $ftoken = $mgr->lock({ 'path' => '/bar', 'owner' => 'fred' });
    like( $ftoken, $token_re, 'non-infinity: fred locks bar' );
    isnt( $token, $ftoken, 'non-infinity: Tokens do not match' );
}

