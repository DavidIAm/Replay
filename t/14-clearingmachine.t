#!/usr/bin/perl

use lib 'Replay/lib/';

package Primera;
use Moose;
use Replay 0.02;
with qw/Replay::Role::Envelope/;

has '+MessageType' => ( default => 'Primera' );
has 'decided'  => (
    is          => 'ro',
    isa         => 'Num',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'message' },
);

package Mediar;
use Moose;
with qw/Replay::Role::Envelope/;
extends 'Replay::Message';
has '+MessageType' => ( default => 'Mediar' );
has 'that'     => (
    is          => 'ro',
    isa         => 'Str',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'message' },
);

package Ultima;
use Moose;
with qw/Replay::Role::Envelope/;
extends 'Replay::Message';
has '+MessageType' => ( default => 'Ultima' );
has 'disaster' => (
    is          => 'ro',
    isa         => 'Str',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'message' },
);

package Lastima;
use Moose;
with qw/Replay::Role::Envelope/;
extends 'Replay::Message';
has '+MessageType' => ( default => 'Lastima' );
has 'this'     => (
    is          => 'ro',
    isa         => 'Str',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'message' },
);
has 'the' => (
    is          => 'ro',
    isa         => 'Str',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'message' },
);
has 'message' => (
    is          => 'ro',
    isa         => 'Str',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'message' },
);
has 'continues' => (
    is          => 'ro',
    isa         => 'Str',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'message' },
);
has 'workflow' => (
    is          => 'ro',
    isa         => 'Str',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'message' },
);

package TESTRULE;

use Moose;
use Replay::Types::Types;
with 'Replay::Role::ClearingMachine' => { -version => 0.02 };
with 'Replay::Role::BusinessRule'    => { -version => 0.02 };

has name => ( is => 'ro', isa => 'Str', default => 'TESTRULE' );
has version => ( is => 'ro', isa => 'Str', default => '1' );

# We start this state by listening for a particular message.  How do we
# recognize it?
sub initial_match {
    my ($self, $message) = @_;
    return $message->{MessageType} eq 'Primera';
}

# We don't manage the key, but we DO manage the values!
sub value_set {
    my ($self, $message) = @_;
    return $message->{Message};
}

# do our thing that requires further input as relevant
sub attempt {
    my ($self, $initial, @rest) = @_;
    return { decided => $initial->success < scalar @rest };
}

# do our thing that requires further input as relevant
sub is_success {
    my ($self, $result) = @_;
    return $result->{decided} > 0;
}

# happens when it is success.  Here you should emit the message that carries on
# the workflow from here.
sub on_success {
    my ($self, $initial, @rest) = @_;
    return Lastima->new(
        this      => 'is',
        the       => 'new',
        message   => 'that',
        continues => 'the',
        workflow  => 'finally'
    );
}

# happens when it is not success.  Probably only relevant to acocunting and
# reporting as to the success rates of this particular clearingmachine
# workflow
sub on_error {
    return Mediar->new(that => 'is');
}

# happens when there are too many errors.  Here you should emit the message
# that fulfills business rules for continuing on error
sub on_exception {
    return Ultima->new(diasaster => 'dispatch the drones');
}

package main;

use Test::Most tests => 10;
use Time::HiRes qw/gettimeofday/;
use Data::Dumper;

my $tr = new TESTRULE->new;

use Replay::Message::Timing;

die unless $tr->version;
is $tr->version, 1, 'version returns';

my $intmessage    = Primera->new( decided => 0 )->marshall;
my $boringmessage = { MessageType => 'boring',      Message => {} };

ok $tr->match($intmessage), 'is interesting';
ok !$tr->match($boringmessage), 'is not interesting';

my $nowindowmessage = { MessageType => 'Primera', EffectiveTime => 'notReallyATime' };
my $windowmessage   = { MessageType => 'ClearingMachine', Message => { window => 'sometime' } };
ok $tr->window($nowindowmessage), 'notReallyATime';
ok $tr->window($windowmessage),   'sometime';

my $funMessage = { MessageType => 'Primera',
    UUID => 'fakeUUID', b => [ 1, 2, 3, 4, 5, 6 ] };
my $secondMessage = { MessageType => 'interesting',
    Message => { c => [ 6, 7, 8, 9, 10 ], } };

use Replay::Message::Envelope;
my $d = +Replay::Message::Envelope->new($funMessage)->marshall;
is $d->{UUID}, 'fakeUUID';
ok exists $d->{CreatedTime}, 'Created exists';
is $d->{Replay}, '20140727';
is $d->{MessageType}, 'Primera';
ok exists $d->{EffectiveTime}, 'EffectiveTime exists';
ok exists $d->{ReceievedTime}, 'ReceievedTime exists';

is_deeply [ $tr->key_value_set( Replay::Message::Envelope->new($funMessage)->marshall) ],
    [ 'fakeUUID-1' => { payload => { b => [ 1, 2, 3, 4, 5, 6 ] } } ], 'copies';

is_deeply [ $tr->key_value_set( Primera->new(  UUID => 'YesAnotherNotAUUID', MessageType => 'Primera', b => [ 1, 2, 3, 4 ] )->marshall ) ],
    [ 'YesAnotherNotAUUID-1' => { payload => { } } ];# b => [ 1, 2, 3, 4 ] } } ];

my $replay = Replay->new(
    config => {
        QueueClass  => 'Replay::EventSystem::Null',
        StorageMode => 'Memory',
        timeout     => 5,
        stage       => 'testscript-04-' . $ENV{USER},
    },
    rules => [ new TESTRULE ]
);

$replay->worm;
$replay->reducer;
$replay->mapper;

is_deeply [
    $replay->storageEngine->fetch_canonical_state(
        Replay::IdKey->new(
            { name => 'TESTRULE', version => 1, window => 'alltime', key => 'a' }
        )
    )
    ],
    [], 'nonexistant';

# automatically stop once we get both new canonicals
my $canoncount = -2;
use Scalar::Util;
$replay->eventSystem->origin->subscribe(
    sub {
        my ($message) = @_;

        warn __FILE__
            . ": This is a origin message of type "
            . $message->{MessageType} . "\n";
    }
);
$replay->eventSystem->map->subscribe(
    sub {
        my ($message) = @_;

        warn __FILE__
            . ": This is a derived message of type "
            . $message->{MessageType} . "\n";
    }
);
$replay->eventSystem->control->subscribe(
    sub {
        my ($message) = @_;

        warn __FILE__
            . ": This is a control message of type "
            . $message->{MessageType} . "\n";

        return unless $message->{MessageType} eq 'NewCanonical';
        return if ++$canoncount;
        $replay->eventSystem->stop;
    }
);

my $time = gettimeofday;
use AnyEvent;
my $e = AnyEvent->timer(
    after => 1,
    cb    => sub {
        $replay->eventSystem->map->emit($funMessage);
        $replay->eventSystem->map->emit($secondMessage);
    }
);
$replay->eventSystem->run;

is_deeply [
    $replay->storageEngine->fetch_canonical_state(
        Replay::IdKey->new(
            { name => 'TESTRULE', version => 1, window => 'alltime', key => 'a' }
        )
    )
    ],
    [15];

is_deeply $replay->storageEngine->window_all(
    Replay::IdKey->new(
        { name => 'TESTRULE', version => 1, window => 'alltime', key => 'a' }
    )
    ),
    { a => [15], c => [40] }, "windowall returns all";

my $idkey = Replay::IdKey->new(
    { name => 'TESTRULE', version => 1, window => 'alltime', key => 'x' });

