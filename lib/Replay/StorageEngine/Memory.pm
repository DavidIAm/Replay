package Replay::StorageEngine::Memory;

use Moose;
use Scalar::Util qw/blessed/;
use Replay::IdKey;

extends 'Replay::BaseStorageEngine';

my $store = {};

override retrieve => sub {
    my ($self, $idkey) = @_;
    super();
    return $store->{ $idkey->collection }{ $idkey->cubby } ||= {};
};

# State transition = add new atom to inbox
override absorb => sub {
    my ($self, $idkey, $atom) = @_;
    my $state = $store->{ $idkey->collection }{ $idkey->cubby } ||= {};
    push @{ $state->{inbox} ||= [] }, $atom;
    super();
    return 1;
};

override checkout => sub {
    my ($self, $idkey) = @_;
    my $hash = $idkey->hash;
    return if exists $self->{checkouts}{$hash};
    $self->{checkouts}{$hash} = $store->{ $idkey->collection }{ $idkey->cubby } ||= {};
    $self->{checkouts}{$hash}{desktop} = delete $self->{checkouts}{$hash}{inbox};
    super();
    return $hash, $self->{checkouts}{$hash}
};

override checkin => sub {
    my ($self, $idkey, $uuid, $state) = @_;
		warn "CHECKIN MEMORY";
    die "not checked out" unless exists $self->{checkouts}{$uuid};
    my $data = delete $self->{checkouts}{$uuid};
    delete $data->{desktop};
    super();
    $store->{ $idkey->collection }{ $idkey->cubby } = $data;
};

#sub fullDump {
#    my $self = shift;
#    return $store;
#}

1;
