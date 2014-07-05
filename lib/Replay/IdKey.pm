package Replay::IdKey;

use Moose;
use MongoDB;
use MooseX::Storage;
use MongoDB::OID;
use Digest::MD5 qw/md5_hex/;

has name    => (is => 'rw', isa => 'Str', required => 1,);
has version => (is => 'rw', isa => 'Str', required => 1,);
has window  => (is => 'rw', isa => 'Str', required => 1,);
has key     => (is => 'rw', isa => 'Str', required => 1,);

with Storage('format' => 'JSON');

sub collection {
    my ($self) = @_;
    return 'replay-' . $self->name . $self->version;
}

sub windowPrefix {
    my ($self) = @_;
    return 'wind-' . $self->window . '-key-';
}

sub cubby {
    my ($self) = @_;
    return $self->windowPrefix . $self->key;
}

sub ruleSpec {
    my ($self) = @_;
    return 'rule-' . $self->name . '-version-' . $self->version;
}

sub hashList {
    my ($self) = @_;
    return (
        name    => $self->name,
        version => $self->version,
        window  => $self->window,
        key     => $self->key
    );
}

sub checkstring {
    my ($self) = @_;
    $self->name($self->name . '');
    $self->version($self->version . '');
    $self->window($self->window . '');
    $self->key($self->key . '');
}

sub hash {
    my ($self) = @_;
    $self->checkstring;
    return md5_hex($self->freeze);
}

sub marshall {
    my ($self) = @_;
    return ( name => $self->name, version => $self->version, window => $self->window, key => $self->key );
}
1;
