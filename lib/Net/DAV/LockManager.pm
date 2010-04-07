package Net::DAV::LockManager;

use strict;
use warnings;

use File::Spec ();
use Net::DAV::UUID;

my $MAX_LOCK_TIMEOUT        = 15 * 60;
my $DEFAULT_LOCK_TIMEOUT    = $MAX_LOCK_TIMEOUT;

sub new {
    my ($class, $db) = (shift, shift);
    my %obj = @_;

    $obj{'db'} = $db;

    return bless \%obj, $class;
}

sub can_modify {
    my ($self, $req) = @_;

    _validate_lock_request( $req );

    my ($resource, $token) = @{$req}{qw/path owner token/};
    my $lock = $self->_get_lock( $resource ) || $self->_get_indirect_lock( $resource );

    return 1 unless $lock;
    return unless $token;

    #
    # Return based on whether or not any operations made by the requestor
    # are permitted based on the current lock.
    #
    return _is_permitted( $req, $lock );
}

sub _get_indirect_lock {
    my ($self, $res) = @_;

    while ( $res =~ s{/[^/]+$}{} ) {
        $res = '/' unless length $res;

        my $lock = $self->_get_lock( $res );
        return $lock if $lock && $lock->depth eq 'infinity';
    }

    return;
}

sub lock {
    my ($self, $req) = @_;

    #
    # Validate the given lock request.  Any errors in validation should
    # percolate through the stack to this point.  It is the caller's
    # responsibility to eval() for such conditions.
    #
    _validate_lock_request( $req );

    my $path = $req->{'path'};
    my $timeout = $req->{'timeout'} || $DEFAULT_LOCK_TIMEOUT;

    #
    # If the lock timeout requested by the user is greater than the hard-coded
    # maximum, then assume the value of the maximum.
    #
    $timeout = $MAX_LOCK_TIMEOUT if $timeout > $MAX_LOCK_TIMEOUT;

    #
    # Calculate the expiration date of this lock based on the lifetime of the
    # lock specified by the client in seconds.
    #
    my $expiry = time() + $timeout;

    #
    # Return with an undef unless this resource can be modified by the current
    # user, and there is not already a lock present.
    #
    return unless $self->can_modify( $req ) && !$self->_get_lock( $path );

    #
    # Create and return a new lock as added from the database with the information
    # provided.  The new lock object, upon creation, will have calculated its own
    # UUID/token information.
    #
    return $self->_add_lock(Net::DAV::Lock->new({
        'path'      => $path,
        'expiry'    => $expiry,
        'owner'     => $req->{'owner'},
        'depth'     => $req->{'depth'},
        'scope'     => $req->{'scope'} || 'exclusive' # 0 or exclusive
    }));
}

sub refresh_lock {
    my ($self, $req) = @_;

    #
    # Validate token specified in the request.
    #
    _validate_lock_request( $req, 'token' );

    #
    # Attempt to obtain a lock which may be present for the current resource.
    #
    my $lock = $self->_get_lock( $req->{'path'} );

    #
    # Return early if there is not currently a lock on the resource, if the
    # requestor is not the owner of the lock, or if the token specified by
    # the client is not the same as the token presently assigned to the lock
    # found in the database.
    #
    return unless _is_permitted( $req, $lock );

    #
    # Renew the lock for the given interval as specified by the client.  If
    # no timeout was specified by the client, then assume the default value
    # as listed in this package.
    #
    my $expiry = time() + ($req->{'timeout'} || $DEFAULT_LOCK_TIMEOUT);

    $lock->renew( $expiry );

    #
    # Finally, the lock may be updated.
    #
    return $self->_update_lock( $lock );
}

sub unlock {
    my ($self, $req) = @_;

    #
    # Ensure the token passed in the unlocking request is valid.
    #
    _validate_lock_request( $req, 'token' );

    #
    # Attempt to obtain the lock based on the path specified in the request.
    #
    my $lock = $self->_get_lock( $req->{'path'} );

    #
    # Return early unless the request is appropriate for the current lock.
    #
    return unless _is_permitted( $req, $lock );

    #
    # Clear the lock without further ado.
    #
    $self->_clear_lock( $lock );

    return 1;
}

#
# Retrieve a lock from the lock database, given the path to the lock.
# Return undef if none.  This method also has the side effect of expiring
# any old locks persisted upon fetching.
#
sub _get_lock {
    my ($self, $path) = @_;

    my $lock = $self->{'db'}->get( $path );

    #
    # Return undef if no lock was found.
    #
    return undef unless $lock;

    #
    # If the lock is past its expiration date, take the opportunity
    # to invalidate it in the database.  Subsequently return undef.
    #
    if (time() >= $lock->expiry) {
        $self->_clear_lock($lock);

        return undef;
    }

    return $lock;
}

#
# Add the given lock to the database.
#
sub _add_lock {
    my ($self, $lock) = @_;

    return $self->{'db'}->add($lock);
}

#
# Update the lock provided.  Currently, only the expiration date
# may be updated.
#
sub _update_lock {
    my ($self, $lock) = @_;

    return $self->{'db'}->update($lock);
}

#
# Remove the lock object passed from the database.
#
sub _clear_lock {
    my ($self, $lock) = @_;

    $self->{'db'}->remove($lock);

    return 1;
}

#
# Return true or false depending on whether or not the information reflected
# in the request is appropriate for the lock obtained from the database.
#
sub _is_permitted {
    my ($req, $lock) = @_;

    #
    # As no lock was passed, return false.
    #
    return 0 unless $lock;

    #
    # Return false if the current requestor is not the owner of the lock.
    #
    return 0 unless $req->{'owner'} eq $lock->owner;

    #
    # Return false if the token specified in the request is different from
    # that of the lock passed.
    #
    return 0 unless $req->{'token'} eq $lock->token;

    #
    # The request passed is appropriate for this lock.
    #
    return 1;
}

#
# Perform general parameter validation.
# The parameter passed in should be a hash reference to be validated.
# The optional list that follows are names of required parameters besides the
#   'path' and 'owner' parameters that are always required.
# Throws exception on failure.
sub _validate_lock_request {
    my ($req, @required) = @_;
    die "Parameter should be a hash reference.\n" unless 'HASH' eq ref $req;
    foreach my $arg ( qw/path owner/, @required ) {
        die "Missing required '$arg' parameter.\n" unless exists $req->{$arg};
    }
    die "Not a clean path\n" if $req->{'path'} =~ m{(?:^|/)\.\.?(?:$|/)};
    die "Not a clean path\n" if $req->{'path'} !~ m{^/} || $req->{'path'} =~ m{./$};
    die "Not a valid owner name.\n" unless $req->{'owner'} =~ m{^[a-z_.][-a-z0-9_.]*$}i;  # May need better validation.

    # Validate optional parameters as necessary.
    if( exists $req->{'scope'} && 'exclusive' ne $req->{'scope'} ) {
        die "'$req->{'scope'}' is not a supported value for scope.\n";
    }
    if( exists $req->{'depth'} && '0' ne $req->{'depth'} && 'infinity' ne $req->{'depth'} ) {
        die "'$req->{'depth'}' is not a supported value for depth.\n";
    }
    if( exists $req->{'timeout'} && $req->{'timeout'} =~ /\D/ ) {
        die "'$req->{'timeout'}' is not a supported value for timeout.\n";
    }
    return;
}
