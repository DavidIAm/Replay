package Replay::Reducer;

=pod

=head1 NAME 

Reducer

=head1 SYNOPSIS

my $eventSystem = Replay::EventSystem->new(config => $config);
my $reducer = Replay::Reducer->new(
   ruleSource => $ruleSource,
   eventSystem => $eventSystem,
   storageengine => $storageEngine
 );
$eventSystem->run;

=head1 DESCRIPTION

The reducer listens for Replay::Message::Reducable messages on the control channel

When it sees one, it attempts to retrieve the rule from its rule source.

If it finds the rule, it attempts to retrieve the transitional state from the engine

If it gets the transitional state, it retrieves the state with the reduce method of the rule

=cut

use Moose;
use Scalar::Util;
use Replay::DelayedEmitter;
use Scalar::Util qw/blessed/;
use Try::Tiny;

has ruleSource => (is => 'ro', isa => 'Replay::RuleSource', required => 1);

has eventSystem => (is => 'ro', isa => 'Replay::EventSystem', required => 1);

has storageEngine =>
    (is => 'ro', isa => 'Replay::StorageEngine', required => 1,);

sub BUILD {
    my $self = shift;
    $self->eventSystem->control->subscribe(
        sub {
            $self->reduceWrapper(@_);
        }
    );
}

# accessor - how to get the rule for an idkey
sub rule {
    my ($self, $idkey) = @_;
    my $rule
        = $self->ruleSource->byNameVersion($idkey->{name}, $idkey->{version});
    die "No such rule $idkey->{name} => $idkey->{version}" unless $rule;
    return $rule;
}

sub reduceWrapper {
    my ($self, $message) = @_;
    return unless blessed $message && $message->isa('Replay::Message::Reducable');
    my $idkey = Replay::IdKey->new(
        {   name    => $message->name,
            version => $message->version,
            window  => $message->window,
            key     => $message->key,
        }
    );
    my ($signature, $meta, @state)
        = $self->storageEngine->fetchTransitionalState($idkey);
    do { $self->storageEngine->revert($idkey, $signature) if $signature; return; }
        unless scalar @state;    # nothing to do!
    my $emitter = Replay::DelayedEmitter->new(eventSystem => $self->eventSystem,
        %{$meta});

    try {
        if ($self->storageEngine->storeNewCanonicalState(
                $idkey, $signature, $self->rule($idkey)->reduce($emitter, @state)
            )
            )
        {
            $emitter->release();
        }
    }
    catch {
        warn "REDUCING EXCEPTION: $_";
        $self->storageEngine->revert($idkey, $signature);
        $self->eventSystem->control->emit(
            CargoTel::Message->new(
                messageType => 'ReducerException',
                message     => {
                    rule      => $self->rule->name,
                    version   => $self->rule->version,
                    exception => (blessed $_ && $_->can('trace') ? $_->trace->as_string : $_),
                    message   => $message
                }
            )
        );
    }
}

1;
