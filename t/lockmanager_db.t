#!/usr/bin/perl

use Test::More tests => 4;
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

my $tests = {
    '/'         => [qw(/foo /foo/bar /foo/bar/baz /foo/meow)],
    '/foo'      => [qw(/foo/bar /foo/bar/baz /foo/meow)],
    '/foo/bar'  => [qw(/foo/bar/baz)]
};

{
    while (my ($ancestor, $descendants) = each(%$tests)) {
        my @locks = $db->list_descendants($ancestor);

        #
        # list_descendants() should return the exact number of items specified
        # in this particular test.
        #
        my $message = sprintf("list_descendants() returned %d items for %s", scalar @$descendants, $ancestor);

        ok(scalar @locks == scalar @$descendants, $message);

        #
        # Check to see if the objects returned are actually the right ones.
        #
        foreach my $path (@$descendants) {
            ok(defined reduce(sub {
                return shift->path eq $path
            }, @locks), "list_descendants() contains lock for $path");
        }
    }
}
