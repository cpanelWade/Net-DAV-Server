#!/usr/bin/perl

use Test::More tests => 1;
use Carp;

use strict;
use warnings;

use Net::DAV::UUID ();

my %uuids = ();

#
# Fill the UUID hash with a UUID as a key 1000 times.  If the number of keys
# found after this test is not exactly 1000, this should be considered a
# failure.
#

for (my $i=0; $i<1000; $i++) {
    $uuids{Net::DAV::UUID::generate("/foo/bar/baz", "tom")} = 1;
}

ok(scalar keys %uuids == 1000, "UUID generator produced 1000 unique identifiers");
