package Replay::StorageEngine;

use Replay::BaseStorageEngine;
use Moose;
use Try::Tiny;

has config => (is => 'ro', isa => 'HashRef[Item]', required => 1,);
has engine => (
    is      => 'ro',
    isa     => 'Replay::BaseStorageEngine',
    builder => '_build_engine',
		lazy => 1,
);
has mode =>
    (is => 'ro', isa => 'Str', required => 1, builder => '_build_mode', lazy => 1);
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
    my $classname = $self->mode;
    return $classname->new(
        config      => $self->config,
        ruleSource  => $self->ruleSource,
        eventSystem => $self->eventSystem,
    );
}

sub _build_mode {
    my $self = shift;
    die "No StorageMode?" unless $self->config->{StorageMode};
    my $class = 'Replay::StorageEngine::' . $self->config->{StorageMode};
    try {
        eval "require $class";
        die $@ if $@;
    }
    catch {
        confess "No such storage mode available ".$self->config->{StorageMode}." --> $_";
    };
		return $class;
}

1;
