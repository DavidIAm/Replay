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
    return $message->{MessageType} eq 'interesting';
};

override keyValueSet => sub {
    my ($self, $message) = @_;
    my @keyvalues = ();
    foreach my $key (keys %{ $message->{Message} }) {
        next unless 'ARRAY' eq ref $message->{Message}{$key};
        foreach (@{ $message->{Message}{$key} }) {
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
use Test::Most tests => 17;
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

is_deeply [ $tr->keyValueSet($funMessage) ],
    [ a => 5, a => 1, a => 2, a => 3, a => 4 ], 'expands';

my $replay = Replay->new(
    config => {
        QueueClass  => 'Replay::EventSystem::Null',
        StorageMode => 'Mongo',
        MongoUser => 'replayuser',
        MongoPass => 'replaypass',
        timeout     => 5,
        stage       => 'testscript-02-' . $ENV{USER},
    },
    rules => [ new TESTRULE ]
);
my $ourtestkey = Replay::IdKey->new(
    { name => 'TESTRULE', version => 1, window => 'alltime', key => 'a' });
warn "REMOVE RESULT"
    . Dumper $replay->storageEngine->engine->collection($ourtestkey)
    ->remove({});

$replay->worm;
$replay->reducer;
$replay->mapper;

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

my $idkey = Replay::IdKey->new(
    { name => 'TESTRULE', version => 1, window => 'alltime', key => 'x' });

# Manually set up an expired record
$replay->storageEngine->engine->collection($idkey)->insert(
    { idkey => $idkey->cubby },
    {   '$set' => { locked => 'notreallylocked', lockExpireEpoch => time - 50000 }
    },
    { upsert => 0, multiple => 0 },
);

{
    my ($uuid, $dog) = $replay->storageEngine->engine->checkout($idkey, 5);
    ok $uuid, "able to check out block";

    ok $replay->storageEngine->engine->revert($idkey, $uuid), "Able to revert";
}

{
    my ($buuid, $dog) = $replay->storageEngine->engine->checkout($idkey, 5);
    ok $buuid, 'checkout good';

    {
        my ($cuuid, $dog) = $replay->storageEngine->engine->checkout($idkey, 5);
        ok !$cuuid, 'failed while checkout already proper';
    }

    ok $replay->storageEngine->engine->revert($idkey, $buuid), "revert clean";
}

{
    my ($uuid, $dog) = $replay->storageEngine->engine->checkout($idkey, 5);
    ok $uuid, "checked out for error cause";
}

{
    my $r = $replay->storageEngine->engine->collection($idkey)->update(
        { idkey    => $idkey->cubby },
        { '$unset' => { lockExpireEpoch => 1 }, },
        { upsert   => 0, multiple => 0 },
    );

    ok $r->{n}, "The update was successful";
}

{
    my ($uuid, $dog) = $replay->storageEngine->engine->checkout($idkey, 5);

    ok $uuid, "Was able to check it out again";
}

# cleanup
$replay->storageEngine->engine->db->drop;
$replay->eventSystem->clear;

