package Replay::StorageEngine;

use Replay::BaseStorageEngine;
use Replay::StorageEngine::Mongo;
use Replay::StorageEngine::Memory;
use Moose;

has locale => (is => 'ro', isa => 'Config::Locale', required => 1,);
has engine => (
    is      => 'ro',
    isa     => 'Replay::BaseStorageEngine',
    builder => '_build_engine'
);
has mode        => (is => 'ro', isa => 'Str',                 required => 1);
has ruleSource  => (is => 'ro', isa => 'Replay::RuleSource',  required => 1);
has eventSystem => (is => 'ro', isa => 'Replay::EventSystem', required => 1);

# Delegate the api points
sub retrieve {
    my $self = shift;
    $self->engine->retrieve(@_);
}

sub absorb {
    my $self = shift;
    $self->engine->absorb(@_);
}

sub fetchCanonicalState {
    my $self = shift;
    $self->engine->fetchCanonicalState(@_);
}

sub fetchTransitionalState {
    my $self = shift;
    $self->engine->fetchTransitionalState(@_);
}

sub revert {
    my $self = shift;
    $self->engine->revert(@_);
}

sub store {
    my $self = shift;
    $self->engine->revert(@_);
}

sub storeNewCanonicalState {
    my $self = shift;
    $self->engine->storeNewCanonicalState(@_);
}

sub windowAll {
    my $self = shift;
    $self->engine->windowAll(@_);
}

sub _build_engine {
    my $self      = shift;
    my $classname = 'Replay::StorageEngine::' . $self->mode;
    return $classname->new(
        locale      => $self->locale,
        ruleSource  => $self->ruleSource,
        eventSystem => $self->eventSystem,
    );
}

1;
