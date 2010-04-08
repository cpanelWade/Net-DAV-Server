package Net::DAV::UUID;

use strict;

use Digest::SHA1 qw(sha1_hex);

#
# Given a WebDAV resource path and lock requestor/owner, generate
# a UUID mostly compliant with RFC 4918 section 20.7.  Despite the
# lack of EUI64 identifier in the host portion of the UUID, the
# value generated is likely not cryptographically sound and should
# not be used in production code outside of the limited realm of a
# WebDAV server implementation.
#
sub generate {
    my ($path, $owner) = @_;

    #
    # Obtain a SHA1 sum concatenated from the following elements:
    #
    # * Filesystem path of item to receive a lock token
    # * Lock owner/owner
    # * Current timestamp
    # * Random number seed
    # * Current UID
    # * Process ID
    #
    my $sum = sha1_hex($path . $owner . time() . rand() . $< . $$);

    #
    # Split the SHA1 sum into a series of five tokens of varying
    # lengths.  As per RFC 4918, every component of the UUID should
    # be random, so as to not provide any information which may
    # identify the host node generating said identifier.
    #
    my @tokens = ();
    my $offset = 0;

    foreach my $size (8, 4, 4, 4, 12) {
        push @tokens, substr($sum, $offset, $size);

        $offset += $size;
    }

    return join '-', @tokens;
}

1;

__END__
Copyright (c) 2010, cPanel, Inc. All rights reserved.
This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.
