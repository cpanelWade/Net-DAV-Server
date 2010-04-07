package Net::DAV::UUID;

use strict;

use Digest::SHA1 qw(sha1_hex);

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
