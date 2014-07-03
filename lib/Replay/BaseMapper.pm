package Replay::BaseMapper;

use Moose;

has ruleSource => (is => 'ro', isa => 'Replay::RuleSource',);

has eventSystem => (is => 'ro', required => 1,);

has storageClass => (is => 'ro',);

has storageEngine => (
    is      => 'ro',
    isa     => 'Replay::StorageEngine',
    builder => 'buildStorageSink',
    lazy    => 1,
);

sub buildStorageSink {
    my $self = shift;
    die "no storage class?" unless $self->storageClass;
    $self->storageClass->new(ruleSource => $self->ruleSource);
}

sub BUILD {
    my $self = shift;
    die "need either storageEngine or storageClass"
        unless $self->storageEngine || $self->storageClass;
    $self->eventSystem->derived->subscribe(
        sub {
            $self->map(@_);
        }
    );
}

sub map {
    my $self    = shift;
    my $message = shift;
    while (my $rule = $self->ruleSource->next) {
        next unless $rule->match($message);
        my @all = $rule->keyValueSet($message);
        die "key value list from key value set must be even" if scalar @all % 2;
        my $window = $rule->window($message);
        while (scalar @all) {
            my $key  = shift @all;
            my $atom = shift @all;
            die "unable to store"
                unless $self->storageEngine->absorb(
                Replay::IdKey->new(
                    {   name    => $rule->name,
                        version => $rule->version,
                        window  => $window,
                        key     => $key
                    }
                ),
                $atom,
                {   bundles      => $message->{bundles},
                    domain       => $self->eventSystem->domain,
                    ruleversions => [
                        { rule => $rule->name, version => $rule->version },
                        @{ $message->{ruleversions} || [] }
                    ]
                }
                );
        }
    }
}

1;
