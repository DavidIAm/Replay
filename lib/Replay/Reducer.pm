package Replay::Reducer;

=pod

=head1 NAME 

Reducer

=head1 SYNOPSIS

my $eventSystem = Replay::EventSystem->new(locale => $locale);
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
            key     => $message->key
        }
    );
    my ($signature, @state)
        = $self->storageEngine->fetchTransitionalState($idkey);
    return unless scalar @state;    # nothing to do!
    $self->storageEngine->storeNewCanonicalState($idkey, $signature,
        $self->rule($idkey)->reduce(@state));
}

1;
