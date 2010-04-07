#!/usr/bin/perl

use Test::More tests => 25;
use Carp;

use strict;
use warnings;

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
    foreach my $path ( '', qw{/.. /fred/.. /../fred /fred/../bianca /fred/ fred/ fred} ) {
        did_die( sub { $mgr->lock({ 'path' => $path, 'owner'=>'gwj' }) }, qr/Not a clean path/, "$path: Not an allowed path" );
    }
}

{
    # Owner checking
    my $mgr = Net::DAV::LockManager->new();
    foreach my $owner ( '', qw{aa()bb /fred/ ab+cd 1fred} ) {
        did_die( sub { $mgr->lock({ 'path' => '/fred/foo', 'owner'=>$owner }) }, qr/Not a valid owner/, "$owner Not an allowed owner" );
    }
}

# Validate optional parameters
{
    my $mgr = Net::DAV::LockManager->new();

    did_die( sub { $mgr->lock({ 'path' => '/foo', 'owner' => 'fred', 'scope' => 'xyzzy' }) }, qr/not a supported .* scope/, 'Unknown scope value.' );
    did_die( sub { $mgr->lock({ 'path' => '/foo', 'owner' => 'fred', 'scope' => 'shared' }) }, qr/not a supported .* scope/, '"shared" not currently supported' );

    did_die( sub { $mgr->lock({ 'path' => '/foo', 'owner' => 'fred', 'depth' => '1' }) }, qr/not a supported .* depth/, 'No numerics other than 0 for depth.' );
    did_die( sub { $mgr->lock({ 'path' => '/foo', 'owner' => 'fred', 'depth' => 'xyzzy' }) }, qr/not a supported .* depth/, 'No non-numerics other than inifinity' );

    did_die( sub { $mgr->lock({ 'path' => '/foo', 'owner' => 'fred', 'timeout' => -1 }) }, qr/not a supported .* timeout/, 'Negative timeout not allowed' );
    did_die( sub { $mgr->lock({ 'path' => '/foo', 'owner' => 'fred', 'timeout' => 3.14 }) }, qr/not a supported .* timeout/, 'Only integer timeout allowed' );
    did_die( sub { $mgr->lock({ 'path' => '/foo', 'owner' => 'fred', 'timeout' => 'xyzzy' }) }, qr/not a supported .* timeout/, 'Non-numeric timeout not allowed' );
}

sub did_die {
    my ($code, $regex, $label) = @_;
    if ( eval { $code->(); } ) {
        fail( "$label: no exception" );
        return;
    }
    like( $@, $regex, $label );
}
