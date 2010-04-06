#!/usr/bin/perl

use Test::More 'no_plan'; #tests => 1;
use Carp;

use strict;
use warnings;

use Net::DAV::LockManager ();

# No locks
{
    my $mgr = Net::DAV::LockManager->new();
    ok( $mgr->can_modify({ 'path' => '/', 'owner' => 'fred' }), '/ with no lock' );
    ok( $mgr->can_modify({ 'path' => '/foo', 'owner' => 'fred' }), 'one level with no lock' );
    ok( $mgr->can_modify({ 'path' => '/foo/a/b/c/d/e', 'owner' => 'fred' }), 'multi-level with no lock' );
}
