package Net::DAV::Lock;

use Net::DAV::UUID;

our %properties = (
    "expiry" => 0, "owner" => 0, "depth" => 0, "scope" => 0, "path" => 0, "uuid" => 1
);

sub new {
    my ($class, $hash) = @_;
    my $obj = {};

    while (my ($property, $is_optional) = each(%properties)) {
        #
        # Create read-only accessors for each property listed above.
        #
        no strict "refs";

        *{"$property"} = sub {
            my ($self) = @_;

            return $self->{$property};
        };

        #
        # For non-optional arguments, ensure a value in the hash proviced
        # exists.
        #
        unless ($hash->{$property} || $is_optional) {
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
    unless ($hash->{"uuid"}) {
        $obj->{"uuid"} = Net::DAV::UUID::generate($hash->{"path"}, $hash->{"owner"});
    }

    return bless $obj, $class;
}

#
# Provide a wrapper method to return a token URI based on the UUID
# stored in the current object.
#
sub token {
    my ($self) = @_;

    return "opaquelocktoken:" . $self->uuid;
}

1;
