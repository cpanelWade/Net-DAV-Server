#! /usr/bin/perl

use Test::More tests => 5;
use Carp;

use strict;
use warnings;

use Net::DAV::Lock ();

{
    eval {
        Net::DAV::Lock->new({
            'expiry'    => time() + 120,
            'owner'     => 'klaude',
            'depth'     => 'infinity',
            'scope'     => 'exclusive',
        });
    };

    ok($@ ne '', "Warning was thrown at object creation time for missing path");
}

{
    eval {
        Net::DAV::Lock->new({
            'expiry'    => time() + 120,
            'owner'     => 'kevin',
            'depth'     => 5,
            'scope'     => 'exclusive',
            'path'      => '/foo'
        });
    };

    ok($@ ne '', 'Warning was thrown at object creation time for non-RFC 4918 depth');
}

{
    eval {
        Net::DAV::Lock->new({
            'expiry'    => time() + 120,
            'owner'     => 'kevin',
            'depth'     => 0,
            'scope'     => 'poop',
            'path'      => '/foo'
        });
    };

    ok($@ ne '', 'Warning was thrown at object creation time for unsupported scope');
}

#
# Be certain to check that the lock object enforces proper expiry timestamps
# that are in the future.
#
{
    eval {
        Net::DAV::Lock->new({
            'expiry'    => 100,
            'owner'     => 'klaude',
            'depth'     => 'infinity',
            'scope'     => 'exclusive',
            'path'      => '/foo'
        });
    };

    ok($@ ne '', "Warning was thrown at object construction time for expiry in the past");
}

{
    my $lock = Net::DAV::Lock->new({
        'expiry'    => time() + 120,
        'owner'     => 'klaude',
        'depth'     => 'infinity',
        'scope'     => 'exclusive',
        'path'      => '/foo'
    });

    eval {
        $lock->renew(time() - 20);
    };

    ok($@ ne '', "Warning was thrown at lock renewal time for expiry in the past");
}
