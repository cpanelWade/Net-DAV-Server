package Net::DAV::Lock;

use Net::DAV::UUID;

our $MAX_LOCK_TIMEOUT        = 15 * 60;
our $DEFAULT_LOCK_TIMEOUT    = $MAX_LOCK_TIMEOUT;
our $DEFAULT_DEPTH           = 'infinity'; # as per RFC 4918, section 9.10.3, paragraph 5
our $DEFAULT_SCOPE           = 'exclusive';

sub new {
    my ($class, $hash) = @_;
    my $obj = {};

    die('Missing path value') unless defined $hash->{'path'};
    $obj->{'path'} = $hash->{'path'};

    die('Missing owner value') unless defined $hash->{'owner'};
    die('Owner contains invalid characters') unless $hash->{'owner'} =~ /^[a-z_.][-a-z0-9_.]*$/;
    $obj->{'owner'} = $hash->{'owner'};

    if (defined $hash->{'expiry'}) {
        die('Lock expiry is a date in the past') if $hash->{'expiry'} < time();
        die('Lock expiry exceeds maximum value') if ($hash->{'expiry'} - time() > $MAX_LOCK_TIMEOUT);
        $obj->{'expiry'} = $hash->{'expiry'};
    } elsif (defined $hash->{'timeout'}) {
        die('Lock timeout exceeds maximum value') if ($hash->{'timeout'} > $MAX_LOCK_TIMEOUT);
        $obj->{'expiry'} = time() + $hash->{'timeout'};
    } else {
        $obj->{'expiry'} = time() + $DEFAULT_LOCK_TIMEOUT;
    }

    if (defined $hash->{'depth'}) {
        die('Depth is a non-RFC 4918 value') unless $hash->{'depth'} =~ /^(?:0|infinity)$/;
        $obj->{'depth'} = $hash->{'depth'};
    } else {
        $obj->{'depth'} = $DEFAULT_DEPTH;
    }

    if (defined $hash->{'scope'}) {
        die('Scope is an unsupported value') unless $hash->{'scope'} eq 'exclusive';
        $obj->{'scope'} = $hash->{'scope'};
    } else {
        $obj->{'scope'} = $DEFAULT_SCOPE;
    }

    $obj->{'uri'} = $hash->{'uri'};

    #
    # Calculate and store a new UUID based on the path and owner
    # specified, if none is present.
    #
    unless ($hash->{'uuid'}) {
        $obj->{'uuid'} = Net::DAV::UUID::generate(@{$hash}{qw/path owner/});
    }

    return bless $obj, $class;
}

sub expiry { shift->{'expiry'} };
sub owner { shift->{'owner'} };
sub depth { shift->{'depth'} };
sub scope { shift->{'scope'} };
sub path { shift->{'path'} };
sub uuid { shift->{'uuid'} };


#
# Provide a wrapper method to return a token URI based on the UUID
# stored in the current object.
#
sub token {
    my ($self) = @_;

    return 'opaquelocktoken:' . $self->uuid;
}

#
# Update the expiration date of this lock.  Throw an error if the update
# is not for any time in the future.
#
# The rationale for providing this method as a means of setting a new
# value for the lock expiration date is that without it, the immutable
# nature of this class forces the creation of a new lock object, which
# would be undesirable as the existing UUID should be preserved.
#
sub renew {
    my ($self, $expiry) = @_;

    die('New lock expiration date is not in the future') unless $expiry > time();

    $self->{'expiry'} = $expiry;

    return $self;
}

1;

__END__
Copyright (c) 2010, cPanel, Inc. All rights reserved.
This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.
