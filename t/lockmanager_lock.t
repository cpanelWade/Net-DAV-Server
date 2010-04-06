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

# Verify nesting locks.
{
    my $mgr = Net::DAV::LockManager->new();
    my $token = $mgr->lock({ 'path' => '/', 'owner' => 'fred' });
    like( $token, $token_re, 'lock root, again' );
    ok( !defined $mgr->lock({ 'path' => '/foo', 'owner' => 'fred' }), 'Cannot lock below root' );
    my $ftoken = $mgr->lock({ 'path' => '/foo', 'owner' => 'fred', 'token' => $token });
    like( $ftoken, $token_re, 'Locking with token is allowed' );
}

{
    my $mgr = Net::DAV::LockManager->new();
    my $token = $mgr->lock({ 'path' => '/', 'owner' => 'fred' });
    like( $token, $token_re, 'lock root, again' );

    ok( !defined $mgr->lock({ 'path' => '/foo', 'owner' => 'bianca' }), 'Cannot lock with wrong owner and no token' );
    ok( !defined $mgr->lock({ 'path' => '/foo', 'owner' => 'bianca', 'token' => $token }), 'Cannot lock with wrong owner' );
}


