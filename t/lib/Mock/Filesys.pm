package Mock::Filesys;

use warnings;
use strict;
use Carp;

sub new {
    return bless {
        cwd => '/',
        fs => {
            '/' =>                   'd',
            '/goo' =>                'd',
            '/foo' =>                'd',
            '/foo/bar' =>            'd',
            '/foo/baz' =>            'd',
            '/foo/bar/index.html' => 'f',
            '/foo/bar/text.html'  => 'f',
            '/foo/baz/index.html' => 'f',
            '/test.html' =>          'f',
        }
    };
}
sub test {
    my ($self, $op, $path) = @_;

    if ( $op eq 'e' ) {
        return exists $self->{'fs'}->{$path};
    }
    elsif ( $op eq 'd' ) {
        return unless exists $self->{'fs'}->{$path};
        return $self->{'fs'}->{$path} eq 'd';
    }
    elsif ( $op eq 'f' ) {
        return unless exists $self->{'fs'}->{$path};
        return $self->{'fs'}->{$path} eq 'f';
    }
    else {
        die "Operation $op not implemented.";
    }
}
sub delete {
    my ($self, $path) = @_;
    $path = $self->_full_path( $path );
    return unless $self->test( 'f', $path );
    delete $self->{'fs'}->{$path};
    return 1;
}
sub rmdir {
    my ($self, $path) = @_;
    $path = $self->_full_path( $path );
    return unless $self->test( 'd', $path );
    # Really should check to see if there are any children.
    delete $self->{'fs'}->{$path};
    return 1;
}
sub cwd {
    my ($self) = @_;
    return defined $self->{'cwd'} ? $self->{'cwd'} : '/';
}
sub _full_path {
    my ($self, $path) = @_;
    return '/' unless defined $path;
    return $path if $path =~ m{^/};
    $path = $self->cwd . '/' . $path;
    $path =~ s{//+}{/}g;
    return $path;
}
sub chdir {
    my ($self, $path) = @_;
    $self->{'cwd'} = $self->_full_path( $path );
    return 1;
}
sub _uniq {
    my %seen;
    return grep { !$seen{$_}++ } @_;
}
sub list {
    my ($self, $path) = @_;
    $path = $self->cwd unless defined $path && length $path;
    $path = $self->_full_path( $path );
    return unless $self->test( 'e', $path );
    if ( $self->test( 'd', $path ) ) {
        my $len = length $path;
        my @list = grep { substr( $_, 0, $len ) eq $path } keys %{$self->{'fs'}};
        return grep { length $_ } _uniq map { $_ = substr( $_, $len ); s{^/}{}; s{/.*$}{}; $_ } @list;
    }
    else {
        $path =~ m{/([^/]+)$};
        return $1;
    }
    return;
}


1; # Magic true value required at end of module

