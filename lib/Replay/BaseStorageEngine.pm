package Replay::BaseStorageEngine;

use Readonly;
use Replay::IdKey;

Readonly my $REDUCE_TIMEOUT => 60;

=pod

=head1 NAME

Replay::BaseStorageEngine

=head1 SYNOPSIS

my $engine = Replay::StorageEngine->new(
     ruleSource => $ruleSource,
     eventSystem => $eventSystem,
);

# add a new atom of state information to the inbox of location $idkey
my $success = $engine->absorb($idkey, $atom);

# return the signature, plus the inbox atoms plus the canonical state of location $idkey
# engine will interlock and maintain only one valid reduction signature per
# idkey location.
my ($signature, $cubbyState) = $engine->fetchTransitionalState($idkey);

# having merged the inbox and canonical atoms into a new canonical state
# store this state.  Prove we started at the proper place with signature
my $success = storeNewCanonicalState(signature, state)

# retrieve just the canonical state, usually for consumption.  No locking.
my $state = fetchCanonicalState(idkey)

=head1 DESCRIPTION

The data model consists of a series of locations represented by 'idkey' type.

The ID type has a NAMESPACE series of axis such as 'name', and 'version', but 
could also contain 'domain', 'system', 'worker', 'client', or any other set 
of divisions as suits the application

All id types contain 'window' (the bitemporality axis)

All id types contain 'key' (the reduction grouping axis)

Each state of the application is formed of a series of identically typed objects.

When a rule decides that information may be interesting and may affect the
state, it sends the object with the idkey that it has been mapped to to the
absorb function

The absorb function adds the object to its inbox list, and an event is emitted
on the control channel 'Replay::Message::Reducable' indicating that a state 
transition is possible within this idkey slot.

When a worker hears the Reducable message, it may call the storage engine with the
fetchTransitionalState method.  This may be called by all workers almost 
simultaneously as all workers are available.  If there is no inbox available 
due to being gotten by a previous caller, nothing will be returned.  This lock
transitions the idkey slot to reducing state.  The merge of the inbox and the
canonical state is returned to the caller with a signature.  The signature and 
reduction state is persisted.  A 'Replay::Message::Reducing' message will be 
emitted on the control channel.

When a worker has completed its reduction process, it calls the storage engine
with the storeNewCanonicalState method.  The previously supplied signature
will be used to validate that it is operating on the latest delivered state.  
(it is possible that the reduce timed out, and more entries were added to the
inbox and merged in!)  If the signature does not match, the data is dropped,
the worker should not emit any derived events in relation to the data reduced.
If the signature matches, the canonical state is replaced, the version number
for the canonical state is incremented, a signature for the canonical state 
is stored and success is returned.  Upon successful commit, a 
'Replay::Message::NewCanonical' message will be emitted on the control channel

When any system wishes to get the current canonical state it may call the 
fetchCanonicalState method.  The current canonical state and signature is 
returned to the client. Upon successful commit, a 'Replay::Message::Fetched'
message is emitted on the control channel

=cut

# types:
# - idkey:
#  { name: string
#  , version: string
#  , window: string
#  , key: string
#  }
# - atom
#  { probably a hashref which is an atom of the state for this compartment }
# - state:
#  idkey: the particular state compartment
#  list: the list of atoms within that compartment
# - signature: md5 sum of the : joined elements of the state
# - signedList:
#  - signature:
#  - list:
# interface:
#  - boolean absorb(idkey, atom): accept a new atom into a state
#  - state fetchTransitionalState(idkey): returns a new key-state for reduce processing
#  - boolean storeNewCanonicalState(signature, state): accept a new canonical state
#  - state fetchCanonicalState(idkey): returns the current collective state
# events emitted:
#  - Replay::Message::Fetched - when a canonical state is retrieved
#  - Replay::Message::Reducable - when its possible a reduction can occur
#  - Replay::Message::Reducing - when a reduction lock has been supplied
#  - Replay::Message::NewCanonical - when we've updated our canonical state
# events consumed:
#  - None

use Moose;
use Digest::MD5 qw/md5_hex/;
use Replay::Message::Reducable;
use Replay::Message::Reducing;
use Replay::Message::NewCanonical;
use Replay::Message::Fetched;
use Replay::Message::Locked;
use Replay::Message::Unlocked;
use Replay::Message::WindowAll;
use Storable qw/freeze/;
$Storable::canonical = 1;

Readonly my $READONLY => 1;

has locale => (is => 'ro', isa => 'Config::Locale', required => 1,);

has ruleSource => (is => 'ro', isa => 'Replay::RuleSource', required => 1);

has eventSystem => (is => 'ro', isa => 'Replay::EventSystem', required => 1);

# accessor - how to get the rule for an idkey
sub rule {
    my ($self, $idkey) = @_;
    my $rule = $self->ruleSource->byIdKey($idkey);
    die "No such rule $idkey->ruleSpec" unless $rule;
    return $rule;
}

# merge a list of atoms with the existing list in that slot
sub merge {
    my ($self, $idkey, $alpha, $beta) = @_;
    my @sorted = sort { $self->rule($idkey)->compare($a, $b) } @{$alpha},
        @{$beta};
    return [@sorted];
}

sub checkout {
    my ($self, $idkey) = @_;
    $self->eventSystem->control->emit(
        Replay::Message::Locked->new($idkey->hashList));
}

sub checkin {
    my ($self, $idkey) = @_;
    $self->eventSystem->control->emit(
        Replay::Message::Unlocked->new($idkey->hashList));
}

sub revert {
    my ($self, $idkey) = @_;
    $self->eventSystem->control->emit(
        Replay::Message::Reverted->new($idkey->hashList));
}

sub retrieve {
    my ($self, $idkey) = @_;
    $self->eventSystem->control->emit(
        Replay::Message::Fetched->new($idkey->hashList));
}

sub absorb {
    my ($self, $idkey) = @_;
    $self->eventSystem->control->emit(
        Replay::Message::Reducable->new($idkey->hashList));
}

# accessor - given a state, generate a signature
sub stateSignature {
    my ($self, $idkey, $list) = @_;
    return undef unless defined $list;
    return md5_hex($idkey->hash . freeze($list));
}

sub fetchTransitionalState {
    my ($self, $idkey) = @_;

    my ($signature, $cubby) = $self->checkout($idkey, $REDUCE_TIMEOUT);

    return unless $signature && $cubby && scalar @{ $cubby->{desktop} || [] };

    # merge in canonical, moving atoms from desktop
    my $reducing
        = $self->merge($idkey, $cubby->{desktop}, $cubby->{canonical} || []);

    # notify interested parties
    $self->eventSystem->control->emit(
        Replay::Message::Reducing->new($idkey->hashList));

    # return signature and list
    return $signature => @{$reducing};
}

sub storeNewCanonicalState {
    my ($self, $idkey, $uuid, @atoms) = @_;
    my $cubby = $self->retrieve($idkey);
    $cubby->{canonVersion}++;
    $cubby->{canonical} = [@atoms];
    $cubby->{canonSignature} = $self->stateSignature($idkey, $cubby->{canonical});
    delete $cubby->{desktop};
    my $newstate = $self->checkin($idkey, $uuid, $cubby);
    $self->eventSystem->control->emit(
        Replay::Message::NewCanonical->new($idkey->hashList));
    $self->eventSystem->control->emit(
        Replay::Message::Reducable->new($idkey->hashList))
        if scalar @{ $newstate->{inbox} || [] }
        ;    # renotify reducable if inbox has entries now
}

sub fetchCanonicalState {
    my ($self, $idkey) = @_;
    my $cubby = $self->retrieve($idkey);
    my $e = $self->stateSignature($idkey, $cubby->{canonical}) || '';
    if (($cubby->{canonSignature} || '') ne ($e || '')) {
        die "canonical corruption $cubby->{canonSignature} vs. " . $e;
    }
    $self->eventSystem->control->emit(
        Replay::Message::Fetched->new($idkey->hashList));
    return @{ $cubby->{canonical} || [] };
}

sub windowAll {
    my ($self, $idkey) = @_;
    $self->eventSystem->control->emit(
        Replay::Message::WindowAll->new($idkey->hashList));
}

sub enumerateWindows {
    my ($self, $idkey) = @_;
    die "unimplemented";
}

sub enumerateKeys {
    my ($self, $idkey) = @_;
    die "unimplemented";
}

1;
