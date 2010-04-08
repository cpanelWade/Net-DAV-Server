#!/usr/bin/perl

use Test::More tests => 1;
use Carp;

use strict;
use warnings;

use Net::DAV::LockManager::DB ();

sub reduce {
    my $test = shift;

    foreach my $item (@_) {
        return $item if $test->($item);
    }
}

#
# Verify that Net::DAV::LockManager::DB->list_descendants() works properly.
#
{
    my $db = Net::DAV::LockManager::DB->new();

    foreach my $path (qw(/ /foo /foo/bar /foo/bar/baz /foo/meow)) {
        $db->add(Net::DAV::Lock->new({
            'expiry'    => time() + 720,
            'owner'     => 'alice',
            'depth'     => 'infinite',
            'scope'     => 'exclusive',
            'path'      => $path
        }));
    }

    my @locks = $db->list_descendants('/foo');

    #
    # list_descendants() should return exactly three items.
    #
    ok(scalar @locks == 3, "Net::DAV::LockManager::DB->list_descendants() returns expected number of results");

    #
    # Check to see if the objects returned are actually the right ones.
    #
    foreach my $path (qw(/foo/bar /foo/bar/baz /foo/meow)) {
        ok(defined reduce(sub {
            return shift->path eq $path
        }, @locks), "Net::DAV::LockManager::DB->list_descendants() contains lock for $path");
    }

    $db->close();
}
