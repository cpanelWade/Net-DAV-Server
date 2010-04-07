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

    _validate_lock_request( $req );

    my $path = $req->{'path'};
    my $timeout = $req->{'timeout'} || $DEFAULT_LOCK_TIMEOUT;

    $timeout = $MAX_LOCK_TIMEOUT if $timeout > $MAX_LOCK_TIMEOUT;

    my $expiry = time() + $timeout;

    return unless $self->can_modify( $req ) && !$self->_get_lock( $path );

    return $self->_add_lock(Net::DAV::Lock->new({
        'path'      => $path,
        'expiry'    => $expiry,
        'owner'     => $req->{'owner'},
        'depth'     => $req->{'depth'},
        'scope'     => $req->{'scope'} || 'exclusive'
    }));
}

sub refresh_lock {
    my ($self, $req) = @_;
    _validate_lock_request( $req, 'token' );

    my $lock = $self->_get_lock( $req->{'path'} );
    return unless _is_permitted( $req, $lock );

    $lock->renew( time() + ($req->{'timeout'} || $DEFAULT_LOCK_TIMEOUT) );

    return $self->_update_lock( $lock );
}

sub unlock {
    my ($self, $req) = @_;
    _validate_lock_request( $req, 'token' );

    my $lock = $self->_get_lock( $req->{'path'} );
    return unless _is_permitted( $req, $lock );

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

    return undef unless $lock;

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
# Update the lock provided.
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
# in the request is appropriate for the lock obtained from the database.  In
# other words, make sure the token and owner match the request.
#
sub _is_permitted {
    my ($req, $lock) = @_;

    return 0 unless $lock;
    return 0 unless exists $req->{'owner'} && $req->{'owner'} eq $lock->owner;
    return 0 unless exists $req->{'token'} && $req->{'token'} eq $lock->token;

    return 1;
}

#
# Perform general parameter validation.
#
# The parameter passed in should be a hash reference to be validated.  The
# optional list that follows are names of required parameters besides the
# 'path' and 'owner' parameters that are always required.
#
# Throws exception on failure.
#
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
