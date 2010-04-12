#! /usr/bin/perl

use Test::More tests => 19;
use Carp;

use strict;
use warnings;

use Net::DAV::Lock ();

{
    my $lock = Net::DAV::Lock->new({
        'owner'     => 'gary',
        'path'      => '/foo/bar'
    });

    ok($lock->expiry - time() >= $Net::DAV::Lock::DEFAULT_LOCK_TIMEOUT, 'Default lock expiry is assumed at instantiation');
    ok($lock->depth eq $Net::DAV::Lock::DEFAULT_DEPTH, 'Default depth is assumed at instantiation');
    ok($lock->scope eq $Net::DAV::Lock::DEFAULT_SCOPE, 'Default scope is assumed at instantiation');
}

{
    eval {
        Net::DAV::Lock->new({
            'owner' => 'f00$bar*!#',
            'path'  => '/foo/bar'
        });
    };

    ok($@ ne '', 'Invalid usernames cause an error to be thrown');
}

{
    my $uuid = 'deadbeef-1337-cafe-babe-f00fd00dc475';

    my $lock = Net::DAV::Lock->new({
        'owner'     => 'gary',
        'path'      => '/foo/bar',
        'uuid'      => $uuid
    });

    ok($lock->uuid eq $uuid, 'UUID accepted at object instantiation time');
}

{
    my $uuid = 'deadbeef-1337-cafe-babe-f00fd00dc475';

    my $lock = Net::DAV::Lock->new({
        'owner'     => 'gary',
        'path'      => '/foo/bar',
        'token'     => "opaquelocktoken:$uuid"
    });

    ok($lock->uuid eq $uuid, 'UUID in token URI format is allowed at instantiation time and parsed properly');
}

{
    my $uuid = 'deadbeef-1337-cafe-babe-f00fd00dc475';

    eval {
        Net::DAV::Lock->new({
            'owner'     => 'gary',
            'path'      => '/foo/bar',
            'token'     => "poop:$uuid"
        });
    };

    ok($@ ne '', 'Error is thrown when token with invalid URI prefix is passed');
}

{
    my $uuid = 'deadbeef-l33t-cafe-babe-f00fd00dc475';

    eval {
        Net::DAV::Lock->new({
            'owner'     => 'gary',
            'path'      => '/foo/bar',
            'token'     => "opaquelocktoken:$uuid"
        });
    };

    ok($@ ne '', 'Error is thrown when token with invalid UUID suffix is passed');
}

{
    my $uuid = 'deadbeef-l33t-cafe-babe-f00fd00dc475';

    eval {
        Net::DAV::Lock->new({
            'owner' => 'gary',
            'path'  => '/foo/bar',
            'uuid'  => "$uuid"
        });
    };

    ok($@ ne '', 'Error is thrown when invalid UUID is passed');
}

{
    my $lock = Net::DAV::Lock->new({
        'owner'     => 'gary',
        'path'      => '/foo/bar',
        'timeout'   => 300
    });

    ok($lock->expiry >= time(), 'Timeout value instead of expiry is allowed at instantiation');
}

{
    eval {
        Net::DAV::Lock->new({
            'path'      => '/foo/bar',
            'owner'     => 'cecil',
            'expiry'    => time() + $Net::DAV::Lock::MAX_LOCK_TIMEOUT + 1
        });
    };

    ok($@ ne '', 'Warning is thrown when an expiry beyond the maximum is specified');
}

{
    eval {
        Net::DAV::Lock->new({
            'path'      => '/foo/bar',
            'owner'     => 'cecil',
            'timeout'   => $Net::DAV::Lock::MAX_LOCK_TIMEOUT + 1
        });
    };

    ok($@ ne '', 'Warning is thrown when a timeout beyond the maximum is specified');
}

{
    eval {
        Net::DAV::Lock->new({
            'path'      => '/foo/bar'
        });
    };

    ok($@ ne '', 'Warning is thrown when no owner is specified');
}

{
    eval {
        Net::DAV::Lock->new({
            'expiry'    => time() + 120,
            'owner'     => 'invalid-owner-name#$'
        });
    };

    ok($@ ne '', "Warning was thrown at object creation time for invalid owner");
}

{
    eval {
        Net::DAV::Lock->new({
            'expiry'    => time() + 120,
            'owner'     => 'klaude'
        });
    };

    ok($@ ne '', "Warning was thrown at object creation time for missing path");
}

{
    eval {
        Net::DAV::Lock->new({
            'path'      => '/foo',
            'owner'     => 'kevin',
            'depth'     => 5
        });
    };

    ok($@ ne '', 'Warning was thrown at object creation time for non-RFC 4918 depth');
}

{
    eval {
        Net::DAV::Lock->new({
            'path'      => '/foo',
            'owner'     => 'kevin',
            'scope'     => 'poop'
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
