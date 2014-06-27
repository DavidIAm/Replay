package Replay::StorageEngine::Memory;

use Moose;
use Scalar::Util qw/blessed/;
use Replay::IdKey;

extends 'Replay::BaseStorageEngine';

my $store = {};

override retrieve => sub {
    my ($self, $idkey) = @_;
    $idkey = Replay::IdKey->new($idkey)
        unless blessed $idkey && $idkey->isa('Replay::IdKey');
    super();
    return $store->{ $idkey->name }{ $idkey->version }{ $idkey->window }
        { $idkey->key } ||= {};
};

# State transition = add new atom to inbox
override absorb => sub {
    my ($self, $idkey, $atom) = @_;
    $idkey = Replay::IdKey->new($idkey)
        unless blessed $idkey && $idkey->isa('Replay::IdKey');
    my $state = $self->retrieve($idkey);
    push @{ $state->{inbox} ||= [] }, $atom;
    super();
    return 1;
};

override checkout => sub {
    my ($self, $idkey) = @_;
    $idkey = Replay::IdKey->new($idkey)
        unless blessed $idkey && $idkey->isa('Replay::IdKey');
    my $hash = $idkey->hash;
    return $self->{checkouts}->{$hash} if exists $self->{checkouts}{$hash};
    die "already checked out" if exists $self->{checkouts}{$hash};
    super();
    $self->{checkouts}{$hash} = $self->retrieve($idkey);
    $self->{checkouts}{$hash}{desktop} = delete $self->{checkouts}{$hash}{inbox};
    return $self->{checkouts}{$hash}
};

override checkin => sub {
    my ($self, $idkey) = @_;
    $idkey = Replay::IdKey->new($idkey)
        unless blessed $idkey && $idkey->isa('Replay::IdKey');
    my $hash = $self->idkeyHash($idkey);
    die "not checked out" unless exists $self->{checkouts};
    my $data = delete $self->{checkouts}{$hash};
    delete $data->{desktop};
    super();
    return $self->store($idkey, $data);
};

#sub fullDump {
#    my $self = shift;
#    return $store;
#}

1;
