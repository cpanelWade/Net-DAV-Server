package Net::DAV::LockManager;

use strict;
use warnings;

use File::Spec ();

my $MAX_LOCK_TIMEOUT = 15 * 60;
my $DEFAULT_LOCK_TIMEOUT = $MAX_LOCK_TIMEOUT;

sub new {
    my $class = shift;
    my %obj = @_;
    $obj{'_locks'} = {};

    return bless \%obj;
}

sub can_modify {
    my ($self, $resource, $user, $token) = @_;

    die "Not a clean path\n" if $resource =~ m{(?:^|/)\.\.?(?:$|/)};
    my $lock = $self->_get_lock( $resource );

    if ( $lock ) {
        return $lock->{'owner'} eq $user && $lock->{'token'} eq $token;
    }

    # Check indirect locking, though ancestors.
    my $ancestor = $resource;
    while( $ancestor =~ s{/[^/]+$}{} ) {
        $lock = $self->_get_lock( $ancestor );
        if ( $lock ) {
            next unless $lock->{'depth'} eq 'infinity';
            return $lock->{'owner'} eq $user && $lock->{'token'} eq $token;
        }
    }

    return 1;
}

sub _get_lock {
    my ($self, $path) = @_;
    my $lock = $self->{'_locks'}->{$path};
    return $lock unless $lock;

    if ( time >= $lock->{'expire'} ) {
        $self->_clear_lock( $path );
        return undef;
    }
    return $self->{'_locks'}->{$path};
}

sub _set_lock {
    my ($self, $path, $lock) = @_;
    $self->{'_locks'}->{$path} = $lock;
    return 1;
}

sub _clear_lock {
    my ($self, $path) = @_;
    delete $self->{'_locks'}->{$path};
    return 1;
}

sub lock {
    my ($self, $req) = @_;
    die 

    my $path = $req->{'path'};
    my $timeout = $req->{'timeout'} || $DEFAULT_LOCK_TIMEOUT;
    $timeout = $MAX_LOCK_TIMEOUT if $timeout > $MAX_LOCK_TIMEOUT;
    my $expire = time + $timeout;
    return unless $self->can_modify( $path ) && !$self->_get_lock( $path );

    my $token = $self->_generate_token( $req );

    $self->_set_lock( $path, {
        expire => $expire,
        owner => $req->{'owner'},
        token => $token,
        depth => $req->{'depth'}||'infinity',
        scope => $req->{'scope'}||'exclusive',
    });
    return $token;
}

sub refresh_lock {
    my ($self, $req) = @_;

    die "Not a clean path\n" if $req->{'path'} =~ m{(?:^|/)\.\.?(?:$|/)};
    my $lock = $self->_get_lock( $req->{'path'} );

    return unless $lock && $lock->{'owner'} eq $req->{'owner'} && $lock->{'token'} eq $req->{'token'};

    $lock->{'expire'} = time() + $req->{'timeout'}||$DEFAULT_LOCK_TIMEOUT;

    return $lock->{'token'};
}

sub unlock {
    my ($self, $resource, $user, $token) = @_;

    die "Not a clean path\n" if $resource =~ m{(?:^|/)\.\.?(?:$|/)};
    my $lock = $self->_get_lock( $resource );

    return unless $lock && $lock->{'owner'} eq $user && $lock->{'token'} eq $token;

    $self->_clear_lock( $resource );
    return 1;
}

sub _generate_token {
    my ($self, $req) = @_;

    return 'opaquelocktoken:abcdef01-dead-beef-0bad-0123456789ab';
}

sub _validate_lock_request {
    my ($req) = @_;
    die "Parameter should be a hash reference.\n" unless 'HASH' eq ref $req;

}
