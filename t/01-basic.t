#!/usr/bin/perl

use lib 'Replay/lib/';

package TESTRULE;

use Moose;
use Replay::Types;
use List::Util qw//;
with 'Replay::Role::BusinessRule' => {  -version => 0.02 };

has '+name' => (default => __PACKAGE__,);

sub match {
    my ($self, $message) = @_;
    return $message->{MessageType} eq 'interesting';
}

sub window {
    my ($self, $message) = @_;
    return 'alltime';
}

sub key_value_set {
    my ($self, $message) = @_;
    my @keyvalues = ();
    foreach my $key (keys %{$message->{Message}}) {
        next unless 'ARRAY' eq ref $message->{Message}->{$key};
        foreach (@{ $message->{Message}->{$key} }) {
            push @keyvalues, $key, $_;
        }
    }
    return @keyvalues;
}

sub compare {
    my ($self, $aa, $bb) = @_;
    return ($aa || 0) <=> ($bb || 0);
}

sub reduce {
    my ($self, $emitter, @state) = @_;
    my $response = List::Util::reduce { $a + $b } @state;
}

package main;
use Data::Dumper;

use Replay 0.02;
use Time::HiRes qw/gettimeofday/;
use Test::Most tests => 10;
use Config::Locale;
use JSON;

# test the event transition interface

# an event transition has a match/map

my $interesting = { MessageType => 'interesting', Message => {} };

my $tr = new TESTRULE->new;
die unless $tr->version;
is $tr->version, 1, 'version returns';

my $intmessage    = { MessageType => 'interesting', Message => {} };
my $boringmessage = { MessageType => 'boring',      Message => {} };

ok $tr->match($intmessage), 'is interesting';
ok !$tr->match($boringmessage), 'is not interesting';

my $nowindowmessage = { vindow => 'sometime' };
my $windowmessage   = { window => 'sometime' };
ok $tr->window($nowindowmessage), 'alltime';
ok $tr->window($windowmessage),   'sometime';

my $funMessage = { MessageType => 'interesting',
    Message => { a => [ 5, 1, 2, 3, 4 ], } };
my $notAfterAll
    = { MessageType => 'boring', Message => { b => [ 1, 2, 3, 4, 5, 6 ] } };
my $secondMessage = { MessageType => 'interesting',
    Message => { c => [ 6, 7, 8, 9, 10 ], } };

is_deeply [ $tr->key_value_set($funMessage) ],
    [ a => 5, a => 1, a => 2, a => 3, a => 4 ], 'expands';

is_deeply [ $tr->key_value_set({ Message => { b => [ 1, 2, 3, 4 ] } }) ],
    [ b => 1, b => 2, b => 3, b => 4 ];

my $replay = Replay->new(
    config => {
        QueueClass  => 'Replay::EventSystem::Null',
        StorageMode => 'Memory',
        timeout     => 50,
        stage       => 'testscript-01-' . $ENV{USER},
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
$replay->eventSystem->derived->subscribe(
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
        warn "EMITTING MESSAGES NOW";

        $replay->eventSystem->derived->emit($funMessage);
        $replay->eventSystem->derived->emit($secondMessage);
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

