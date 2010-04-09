#!/usr/bin/perl

use Test::More tests => 32;
use Carp;

use strict;
use warnings;

use Net::DAV::LockManager ();
use Net::DAV::LockManager::Simple ();

use Net::DAV::UUID ();

# No locks
{
    my $db = Net::DAV::LockManager::Simple->new();
    my $mgr = Net::DAV::LockManager->new($db);
    ok( $mgr->can_modify({ 'path' => '/', 'owner' => 'fred' }), '/ with no lock' );
    ok( $mgr->can_modify({ 'path' => '/foo', 'owner' => 'fred' }), 'one level with no lock' );
    ok( $mgr->can_modify({ 'path' => '/foo/a/b/c/d/e', 'owner' => 'fred' }), 'multi-level with no lock' );
}

# Infinity lock on ancestor
{
    my $db = Net::DAV::LockManager::Simple->new();
    my $mgr = Net::DAV::LockManager->new($db);
    my $lck = $mgr->lock({ 'path' => '/', 'owner' => 'fred' });
    my $t = $lck->token;

    ok( !$mgr->can_modify({ 'path' => '/', 'owner' => 'bianca' }), 'different owner, resource with lock, no token' );
    ok( !$mgr->can_modify({ 'path' => '/foo', 'owner' => 'bianca' }), 'different owner, child of resource with lock, no token' );
    ok( !$mgr->can_modify({ 'path' => '/a/b/c/d/e/f', 'owner' => 'bianca' }), 'different owner, descendant of resource with lock, no token' );

    ok( !$mgr->can_modify({ 'path' => '/', 'owner' => 'bianca', 'token' => $t }), 'different owner, resource with lock' );
    ok( !$mgr->can_modify({ 'path' => '/foo', 'owner' => 'bianca', 'token' => $t }), 'different owner, child of resource with lock' );
    ok( !$mgr->can_modify({ 'path' => '/a/b/c/d/e/f', 'owner' => 'bianca', 'token' => $t }), 'different owner, descendant of resource with lock' );
}

# Infinity lock on ancestor
{
    my $db = Net::DAV::LockManager::Simple->new();
    my $mgr = Net::DAV::LockManager->new($db);
    my $lck = $mgr->lock({ 'path' => '/', 'owner' => 'fred' });

    # Warning: Reliance on an implementation detail.
    my $mock_token = 'opaquelocktoken:' . Net::DAV::UUID::generate( '/foo', 'fred' );

    ok( !$mgr->can_modify({ 'path' => '/', 'owner' => 'fred', 'token' => $mock_token }), 'wrong token, resource with lock' );
    ok( !$mgr->can_modify({ 'path' => '/foo', 'owner' => 'fred', 'token' => $mock_token }), 'wrong token, child of resource with lock' );
    ok( !$mgr->can_modify({ 'path' => '/a/b/c/d/e/f', 'owner' => 'fred', 'token' => $mock_token }), 'wrong token, descendant of resource with lock' );
}

# Infinity lock on non-ancestor
{
    my $db = Net::DAV::LockManager::Simple->new();
    my $mgr = Net::DAV::LockManager->new($db);
    my $lck = $mgr->lock({ 'path' => '/foo', 'owner' => 'fred' });

    ok( $mgr->can_modify({ 'path' => '/bar', 'owner' => 'bianca' }), 'different owner, sibling resource, without token' );
    ok( $mgr->can_modify({ 'path' => '/bar/foo', 'owner' => 'bianca' }), 'different owner, child of resource with lock' );
    ok( $mgr->can_modify({ 'path' => '/bar/c/d/e/f', 'owner' => 'bianca' }), 'different owner, descendant of sibling resource with lock' );
}

# Non-Infinity lock on ancestor
{
    my $db = Net::DAV::LockManager::Simple->new();
    my $mgr = Net::DAV::LockManager->new($db);
    my $lck = $mgr->lock({ 'path' => '/', 'owner' => 'fred', 'depth' => 0 });
    my $t = $lck->token;

    ok( !$mgr->can_modify({ 'path' => '/', 'owner' => 'bianca' }), 'different owner, resource with lock, without token' );
    ok( $mgr->can_modify({ 'path' => '/foo', 'owner' => 'bianca' }), 'different owner, child of resource with lock, without token' );
    ok( $mgr->can_modify({ 'path' => '/a/b/c/d/e/f', 'owner' => 'bianca' }), 'different owner, descendant of resource with lock, without token' );

    ok( !$mgr->can_modify({ 'path' => '/', 'owner' => 'bianca', 'token' => $t }), 'different owner, resource with lock' );
    ok( $mgr->can_modify({ 'path' => '/foo', 'owner' => 'bianca', 'token' => $t }), 'different owner, child of resource with lock' );
    ok( $mgr->can_modify({ 'path' => '/a/b/c/d/e/f', 'owner' => 'bianca', 'token' => $t }), 'different owner, descendant of resource with lock' );
}

# Non-Infinity lock on non-ancestor
{
    my $db = Net::DAV::LockManager::Simple->new();
    my $mgr = Net::DAV::LockManager->new($db);
    my $lck = $mgr->lock({ 'path' => '/foo', 'owner' => 'fred', 'depth' => 0 });
    my $t = $lck->token;

    ok( $mgr->can_modify({ 'path' => '/bar', 'owner' => 'bianca' }), 'different owner, sibling resource' );
    ok( $mgr->can_modify({ 'path' => '/bar/c/d/e/f', 'owner' => 'bianca' }), 'different owner, descendant of sibling resource with lock' );
}

# Infinity lock on non-ancestor, multiple-tokens
{
    my $db = Net::DAV::LockManager::Simple->new();
    my $mgr = Net::DAV::LockManager->new($db);
    my $lck = $mgr->lock({ 'path' => '/foo', 'owner' => 'fred' });
    # Warning: Reliance on an implementation detail.
    my $tokens = [
        'opaquelocktoken:' . Net::DAV::UUID::generate( '/baz', 'fred' ), # mock token 1
        $lck->token,                                                     # Correct token
        'opaquelocktoken:' . Net::DAV::UUID::generate( '/bar', 'fred' ), # mock token 2
    ];

    ok( $mgr->can_modify({ 'path' => '/foo', 'owner' => 'fred', 'token' => $tokens }), 'owner, resource, multi-token' );
    ok( $mgr->can_modify({ 'path' => '/foo/bar', 'owner' => 'fred', 'token' => $tokens }), 'owner, child, multi-token' );
    ok( $mgr->can_modify({ 'path' => '/foo/bar/c/d/e/f', 'owner' => 'fred', 'token' => $tokens }), 'owner, descendant, multi-token' );

    ok( !$mgr->can_modify({ 'path' => '/foo', 'owner' => 'bianca', 'token' => $tokens }), 'different owner, resource, multi-token' );
    ok( !$mgr->can_modify({ 'path' => '/foo/bar', 'owner' => 'bianca', 'token' => $tokens }), 'different owner, child, multi-token' );
    ok( !$mgr->can_modify({ 'path' => '/foo/bar/c/d/e/f', 'owner' => 'bianca', 'token' => $tokens }), 'different owner, descendant, multi-token' );

    $tokens = [ @{$tokens}[0,2] ];  # Remove correct token
    ok( !$mgr->can_modify({ 'path' => '/foo', 'owner' => 'fred', 'token' => $tokens }), 'owner, resource, multi-token, all bad' );
    ok( !$mgr->can_modify({ 'path' => '/foo/bar', 'owner' => 'fred', 'token' => $tokens }), 'owner, child, multi-token, all bad' );
    ok( !$mgr->can_modify({ 'path' => '/foo/bar/c/d/e/f', 'owner' => 'fred', 'token' => $tokens }), 'owner, descendant, multi-token, all bad' );
}

