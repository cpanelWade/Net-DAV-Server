package Net::DAV::Lock;

use Net::DAV::UUID;

my %properties = (
    'expiry' => 0, 'owner' => 0, 'depth' => 0, 'scope' => 0, 'path' => 0, 'uuid' => 1
);

sub INIT {
    #
    # Create read-only accessors for each property listed above.
    #
    foreach my $property (keys %properties) {
        no strict 'refs';

        *{$property} = sub {
            return shift->{$property};
        };
    }
}

sub new {
    my ($class, $hash) = @_;
    my $obj = {};

    die('Lock expiry is a date in the past') if $hash->{'expiry'} < time();
    die('Owner contains invalid characters') unless $hash->{'owner'} =~ /^[a-z_.][-a-z0-9_.]*$/;
    die('Depth is a non-RFC 4918 value: ' . $hash->{'depth'}) unless $hash->{'depth'} =~ /^(0|infinity)$/;
    die('Scope is an unsupported value') unless $hash->{'scope'} eq 'exclusive';

    #
    # Copy the required parameters from the anonymous hash provided as
    # input.  Die if any required values are missing.
    #
    while (my ($property, $is_optional) = each(%properties)) {
        #
        # For non-optional arguments, ensure a value in the hash prodided
        # exists.
        #
        unless (defined $hash->{$property} || $is_optional) {
            die("Missing value for '$property' property");
        }

        #
        # Copy the value over from the input hash into the new object.
        #
        $obj->{$property} = $hash->{$property};
    }

    #
    # Calculate and store a new UUID based on the path and owner
    # specified, if none is present.
    #
    unless ($hash->{'uuid'}) {
        $obj->{'uuid'} = Net::DAV::UUID::generate(@{$hash}{qw/path owner/});
    }

    return bless $obj, $class;
}

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
