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
            my ($self) = @_;

            return $self->{$property};
        };
    }
}

sub new {
    my ($class, $hash) = @_;
    my $obj = {};

    #
    # Copy the required parameters from the anonymous hash provided as
    # input.  Die if any required values are missing.
    #
    while (my ($property, $is_optional) = each(%properties)) {
        #
        # For non-optional arguments, ensure a value in the hash prodided
        # exists.
        #
        unless ($hash->{$property} ne undef || $is_optional) {
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
        $obj->{'uuid'} = Net::DAV::UUID::generate($hash->{'path'}, $hash->{'owner'});
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

    die('New lock expiration date is not in the future') unless $expiry - time() > 0;

    $self->{'expiry'} = $expiry;

    return $self;
}

1;
