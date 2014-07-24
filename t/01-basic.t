#!/usr/bin/perl

use lib 'Replay/lib/';

package TESTRULE;

use Replay::BusinessRule;
use Replay::IdKey;
use Moose;
extends 'Replay::BusinessRule';
use List::Util qw//;

has '+name' => (default => __PACKAGE__,);

override match => sub {
    my ($self, $message) = @_;
    return $message->{is_interesting};
};

override keyValueSet => sub {
    my ($self, $message) = @_;
    my @keyvalues = ();
    foreach my $key (keys %{$message}) {
        next unless 'ARRAY' eq ref $message->{$key};
        foreach (@{ $message->{$key} }) {
            push @keyvalues, $key, $_;
        }
    }
    return @keyvalues;
};

override compare => sub {
    my ($self, $aa, $bb) = @_;
    return ($aa || 0) <=> ($bb || 0);
};

override reduce => sub {
    my ($self, $emitter, @state) = @_;
    my $response = List::Util::reduce { $a + $b } @state;
};

package main;
use Data::Dumper;

use Replay;
use Time::HiRes qw/gettimeofday/;
use Test::Most tests => 10;
use Config::Locale;
use JSON;

# test the event transition interface

# an event transition has a match/map

my $interesting = { interesting => 1 };

my $tr = new TESTRULE->new;
die unless $tr->version;
is $tr->version, 1, 'version returns';

my $intmessage    = { is_interesting => 1 };
my $boringmessage = { is_interesting => 0 };

ok $tr->match($intmessage), 'is interesting';
ok !$tr->match($boringmessage), 'is not interesting';

my $nowindowmessage = { vindow => 'sometime' };
my $windowmessage   = { window => 'sometime' };
ok $tr->window($nowindowmessage), 'alltime';
ok $tr->window($windowmessage),   'sometime';

my $funMessage
    = { a => [ 5, 1, 2, 3, 4 ], is_interesting => 1, messageType => 'adhoc' };
my $notAfterAll = { b => [ 1, 2, 3, 4, 5, 6 ] };
my $secondMessage = { c => [ 6, 7, 8, 9, 10 ], is_interesting => 1,
    MessageType => 'adhoc' };

is_deeply [ $tr->keyValueSet($funMessage) ],
    [ a => 5, a => 1, a => 2, a => 3, a => 4 ], 'expands';

is_deeply [ $tr->keyValueSet({ b => [ 1, 2, 3, 4 ] }) ],
    [ b => 1, b => 2, b => 3, b => 4 ];

my $replay = Replay->new(
    config => {
        QueueClass  => 'Replay::EventSystem::Null',
        StorageMode => 'Memory',
        timeout     => 5
    },
    rules => [ new TESTRULE ]
);

$replay->worm;
$replay->reducer;
$replay->mapper;

$replay->eventSystem->derived->emit($funMessage);
$replay->eventSystem->derived->emit($secondMessage);

is_deeply [
    $replay->storageEngine->fetchCanonicalState(
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

        #warn "This is a origin message of type ".$message->{messageType}."\n";
    }
);
$replay->eventSystem->derived->subscribe(
    sub {
        my ($message) = @_;

        #warn "This is a derived message of type ".$message->{messageType}."\n";
    }
);
$replay->eventSystem->control->subscribe(
    sub {
        my ($message) = @_;

        #warn "This is a control message of type ".$message->{messageType}."\n";
        return                     unless blessed $message;
        return                     unless $message->MessageType eq 'NewCanonical';
        $replay->eventSystem->stop unless ++$canoncount;
    }
);

my $time = gettimeofday;
$replay->eventSystem->run;

is_deeply [
    $replay->storageEngine->fetchCanonicalState(
        Replay::IdKey->new(
            { name => 'TESTRULE', version => 1, window => 'alltime', key => 'a' }
        )
    )
    ],
    [15];

is_deeply $replay->storageEngine->windowAll(
    Replay::IdKey->new(
        { name => 'TESTRULE', version => 1, window => 'alltime', key => 'a' }
    )
    ),
    { a => [15], c => [40] }, "windowall returns all";

