package Net::DAV::LockManager;

use strict;
use warnings;

use File::Spec ();
use Net::DAV::UUID;

my $MAX_LOCK_TIMEOUT = 15 * 60;
my $DEFAULT_LOCK_TIMEOUT = $MAX_LOCK_TIMEOUT;

sub new {
    my $class = shift;
    my %obj = @_;
    $obj{'_locks'} = {};

    return bless \%obj;
}

sub can_modify {
    my ($self, $req) = @_;

    _validate_lock_request( $req );

    my ($resource, $user, $token) = @{$req}{qw/path owner token/};
    my $lock = $self->_get_lock( $resource );

    if ( $lock ) {
        return unless $token;
        return $lock->{'owner'} eq $user && $lock->{'token'} eq $token;
    }

    # Check indirect locking, though ancestors.
    my $ancestor = $resource;
    while( $ancestor =~ s{/[^/]+$}{} ) {
        $ancestor = '/' unless length $ancestor;
        $lock = $self->_get_lock( $ancestor );
        if ( $lock ) {
            next unless !exists $lock->{'depth'} || $lock->{'depth'} eq 'infinity';
            return unless $token;
            return $lock->{'owner'} eq $user && $lock->{'token'} eq $token;
        }
    }

    return 1;
}

sub lock {
    my ($self, $req) = @_;
    _validate_lock_request( $req );
    my $path = $req->{'path'};
    my $timeout = $req->{'timeout'} || $DEFAULT_LOCK_TIMEOUT;
    $timeout = $MAX_LOCK_TIMEOUT if $timeout > $MAX_LOCK_TIMEOUT;
    my $expiry = time + $timeout;
    return unless $self->can_modify( $req ) && !$self->_get_lock( $path );

    my $token = $self->_generate_token( $req );

    return $self->_set_lock( $path, {
        expiry => $expiry,
        owner => $req->{'owner'},
        token => $token,
        depth => (exists $req->{'depth'} ? $req->{'depth'} : 'infinity'),
        scope => $req->{'scope'}||'exclusive',
    });
}

sub refresh_lock {
    my ($self, $req) = @_;
    _validate_lock_request( $req, 'token' );

    my $lock = $self->_get_lock( $req->{'path'} );

    return unless $lock && $lock->{'owner'} eq $req->{'owner'} && $lock->{'token'} eq $req->{'token'};

    $lock->{'expiry'} = time() + $req->{'timeout'}||$DEFAULT_LOCK_TIMEOUT;

    return $self->_set_lock( $req->{'path'}, $lock );
}

sub unlock {
    my ($self, $req) = @_;
    _validate_lock_request( $req, 'token' );

    my $lock = $self->_get_lock( $req->{'path'} );

    return unless $lock && $lock->{'owner'} eq $req->{'owner'} && $lock->{'token'} eq $req->{'token'};

    $self->_clear_lock( $req->{'path'} );
    return 1;
}

#
# Retrieve a lock from the lock database, given the path to the lock.
# Return undef if none.
sub _get_lock {
    my ($self, $path) = @_;
    my $lock = $self->{'_locks'}->{$path};
    return $lock unless $lock;

    if ( time >= $lock->{'expiry'} ) {
        $self->_clear_lock( $path );
        return undef;
    }
    return $self->{'_locks'}->{$path};
}

#
# Add a lock to the lock database, given a path and the lock information
# TODO split into set and update
sub _set_lock {
    my ($self, $path, $lock) = @_;
    $self->{'_locks'}->{$path} = $lock;
    return { %$lock };
}

#
# Remove a lock from the lock database
sub _clear_lock {
    my ($self, $path) = @_;
    delete $self->{'_locks'}->{$path};
    return 1;
}

#
# Generate a string appropriate for use as a LOCK token in a WebDAV
# system, given the parameters in $req.
sub _generate_token {
    my ($self, $req) = @_;

    return 'opaquelocktoken:' . Net::DAV::UUID::generate( $req->{'path'}, $req->{'owner'} );
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
    # TODO Add validation for timeout, depth, and scope.
    return;
}
