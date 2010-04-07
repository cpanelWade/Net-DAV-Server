#!/usr/bin/perl

use Test::More tests => 1;
use Carp;

use strict;
use warnings;

use Net::DAV::UUID ();

my %uuids = ();

#
# Fill the UUID hash with a UUID as a key 10000 times.  If the number of keys
# found after this test is not exactly 10000, this should be considered a
# failure.
#

for (my $i=0; $i<10000; $i++) {
    $uuids{Net::DAV::UUID::generate("/foo/bar/baz", "tom")} = 1;
}

ok(scalar keys %uuids == 10000, "UUID generator produced 10000 unique identifiers");
