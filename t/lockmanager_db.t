#!/usr/bin/perl

use Test::More tests => 22;
use Carp;

use strict;
use warnings;

use Net::DAV::LockManager::Simple ();
use Net::DAV::LockManager::DB ();

sub reduce {
    my $test = shift;

    foreach my $item (@_) {
        return $item if $test->($item);
    }
}

my @db_drivers = (
    sub { return ('Net::DAV::LockManager::DB'       => Net::DAV::LockManager::DB->new()) },
    sub { return ('Net::DAV::LockManager::Simple'   => Net::DAV::LockManager::DB->new()) }
);

my $test_data = {
    '/'         => [qw(/foo /foo/bar /foo/bar/baz /foo/meow)],
    '/foo'      => [qw(/foo/bar /foo/bar/baz /foo/meow)],
    '/foo/bar'  => [qw(/foo/bar/baz)]
};

foreach my $db_driver (@db_drivers) {
    my ($db_type, $db) = $db_driver->();

    foreach my $path (qw(/ /foo /foo/bar /foo/bar/baz /foo/meow)) {
        $db->add(Net::DAV::Lock->new({
            'expiry'    => time() + 720,
            'owner'     => 'alice',
            'depth'     => 'infinite',
            'scope'     => 'exclusive',
            'path'      => $path
        }));
    }

    while (my ($ancestor, $descendants) = each(%$test_data)) {
        my @locks = $db->list_descendants($ancestor);

        #
        # list_descendants() should return the exact number of items specified
        # in this particular test.
        #
        my $message = sprintf("%s::list_descendants() returned %d items for %s",
          $db_type, scalar @$descendants, $ancestor);

        ok(scalar @locks == scalar @$descendants, $message);

        #
        # Check to see if the objects returned are actually the right ones.
        #
        foreach my $path (@$descendants) {
            ok(defined reduce(sub {
                return shift->path eq $path
            }, @locks), "$db_type\::list_descendants() contains lock for $path");
        }
    }
}
