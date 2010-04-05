#!/usr/bin/perl

use Test::More tests => 9;
use Carp;

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/..";
use lib "/usr/local/cpanel";

use Net::DAV::LockManager ();


{
    # Validate parameters
    my $mgr = Net::DAV::LockManager->new();
    did_die( sub { $mgr->lock() },                          qr/hash reference/,           'No args' );
    did_die( sub { $mgr->lock( 'fred' ) },                  qr/hash reference/,           'String arg' );
    did_die( sub { $mgr->lock({}) },                        qr/Missing required/,         'No params' );
    did_die( sub { $mgr->lock({ 'owner' => 'gwj' }) },      qr/Missing required 'path'/,  'Missing path' );
    did_die( sub { $mgr->lock({ 'path' => '/tmp/file' }) }, qr/Missing required 'owner'/, 'Missing owner' );
}

{
    # Path checking
    my $mgr = Net::DAV::LockManager->new();
    foreach my $path ( qw{.. fred/.. ../fred fred/../bianca} ) {
        ok( !defined eval { $mgr->lock({ 'path' => $path, 'owner'=>'gwj' }) }, "$path: Not an allowed path" );
    }
}

sub did_die {
    my ($code, $regex, $label) = @_;
    if ( eval { $code->(); } ) {
        fail( "$label: no exception" );
        return;
    }
    like( $@, $regex, $label );
}
