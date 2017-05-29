package Replay::StorageEngine::Lock;

use Moose;
use Digest::MD5 qw/md5_hex/;
use Data::UUID;
use Carp qw/carp confess/;
use Storable qw/freeze/;

our $VERSION = '0.03';

has idkey => ( is => 'ro' );

has uuid => ( is => 'ro', builder => 'generate_uuid' );

has locked => ( is => 'ro', );

has timeout => ( is => 'ro', isa => 'Int', );

has lockExpireEpoch => ( is => 'ro', isa => 'Int', );

sub generate_uuid {
    my ($self)     = @_;
    my $uuid_maker = Data::UUID->new();
    my $string     = $uuid_maker->to_string( $uuid_maker->create );
    return $string;
}

# accessor - given a state, generate a signature
sub state_signature {
    my ( $idkey, $list ) = @_;
    if ( !defined $list ) {return}
    my $sig = md5_hex( $idkey->hash . freeze($list) );
    return $sig;
}

sub is_proper {
    my ( $self, $signature ) = @_;
    return $self->is_mine($signature) && !$self->is_expired;
}

sub is_locked {
    my ( $self, $report ) = @_;
    return $self->locked;
}

sub is_mine {
    my ( $self, $signature ) = @_;
    return $self->locked && $signature && $self->locked eq $signature;
}

sub is_expired {
    my ( $self, $report ) = @_;
    return $self->lockExpireEpoch < time;
}

sub matches {
    my ( $self, $otherlock ) = @_;
    return $self->is_mine( $otherlock->locked )
        && $self->idkey->full_spec eq $otherlock->idkey->full_spec;
}

sub prospective {
    my ( $class, $idkey, $timeout ) = @_;
    my $lock = $class->new(
        {   idkey           => $idkey,
            lockExpireEpoch => time + $timeout,
            locked  => my $sig = state_signature( $idkey, [ $class->generate_uuid ] ),
            timeout => $timeout,
        }
    );
    carp $$ . ' INOUT created lock object for '.$idkey->cubby.' with sig '.$sig;
    return $lock;
}

sub empty {
    my ( $class, $idkey ) = @_;
    confess 'idkey required for empty lock' if !$idkey;
    my $l = $class->new( { idkey => $idkey } );
    return $l;
}

1;
