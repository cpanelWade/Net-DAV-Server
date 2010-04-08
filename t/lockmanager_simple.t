#! /usr/bin/perl

use Test::More tests => 5;
use Carp;

use strict;
use warnings;

use Net::DAV::Lock ();
use Net::DAV::LockManager::Simple ();

my $db = Net::DAV::LockManager::Simple->new();

#
# Add a number of random locks to the database for the sake of branch
# coverage.
#
foreach my $path (qw(/one /two /three)) {
    $db->add(Net::DAV::Lock->new({
        'expiry'    => time() + 720,
        'owner'     => 'conan',
        'depth'     => 0,
        'scope'     => 'exclusive',
        'path'      => $path
    }));
}

my $lock = $db->add(Net::DAV::Lock->new({
    'expiry'    => time() + 720,
    'owner'     => 'conan',
    'depth'     => 0,
    'scope'     => 'exclusive',
    'path'      => '/foo'
}));

ok(ref $lock eq 'Net::DAV::Lock', 'Successfully added lock to database');

$lock = $db->get('/foo');

ok(ref $lock eq 'Net::DAV::Lock', 'Net::DAV::Lock object was returned by database');
ok($lock->owner eq 'conan', 'Lock was recorded with proper owner in database');

$lock->renew(time() + 86400);
ok(ref $db->update($lock) eq 'Net::DAV::Lock', 'Database allows lock updates/renewals');

$db->remove($lock);
ok(!defined $db->get('/foo'), 'Database removes locks properly');
