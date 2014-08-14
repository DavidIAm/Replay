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
use Test::Most tests => 18;
use Config::Locale;
use JSON;

# test the event transition interface

# an event transition has a match/map

my $interesting = { MessageType => 'interesting' };

my $tr = new TESTRULE->new;
die unless $tr->version;
is $tr->version, 1, 'version returns';

my $intmessage    = { MessageType => 'interesting' };
my $boringmessage = { MessageType => 'boring' };

ok $tr->match($intmessage), 'interesting';
ok !$tr->match($boringmessage), 'boring';

my $nowindowmessage = { vindow => 'sometime' };
my $windowmessage   = { window => 'sometime' };
ok $tr->window($nowindowmessage), 'alltime';
ok $tr->window($windowmessage),   'sometime';

my $funMessage
    = { Message => { a => [ 5, 1, 2, 3, 4 ] }, MessageType => 'interesting' };
my $notAfterAll
    = { MessageType => 'Boring', Message => { b => [ 1, 2, 3, 4, 5, 6 ] } };
my $secondMessage = { Message => { c => [ 6, 7, 8, 9, 10 ] },
    MessageType => 'interesting' };

is_deeply [ $tr->keyValueSet($funMessage) ],
    [ a => 5, a => 1, a => 2, a => 3, a => 4 ], 'expands';

is_deeply [ $tr->keyValueSet({ Message => { b => [ 1, 2, 3, 4 ] } }) ],
    [ b => 1, b => 2, b => 3, b => 4 ];

my $replay = Replay->new(
    config => {
        QueueClass  => 'Replay::EventSystem::Null',
        StorageMode => 'Mongo',
        timeout     => 5,
        stage       => 'testscript-' . $ENV{USER},
        Mongo  => { authdb => 'admin', user => 'replayuser', pass => 'replaypass', },
        domain => 'basicmongotest',
    },
    rules => [ new TESTRULE ]
);
#$replay->storageEngine->engine->db->drop;

#goto LATTER;

my $ourtestkey = Replay::IdKey->new(
    { domain => 'basicmongotest', name => 'TESTRULE', version => 1, window => 'alltime', key => 'a' });
warn "clearing collection "
    . $ourtestkey->collection
    . " in db "
    . $replay->storageEngine->engine->dbname()
    . " result is "
    . Dumper $replay->storageEngine->engine->collection($ourtestkey)
    ->drop({});

$replay->worm;
$replay->reducer;
$replay->mapper;

$replay->eventSystem->derived->emit($funMessage);
$replay->eventSystem->derived->emit($secondMessage);

{
    my ($meta, @state) = $replay->storageEngine->fetchCanonicalState(
        Replay::IdKey->new(
            { domain => 'basicmongotest', name => 'TESTRULE', version => 1, window => 'alltime', key => 'a' }
        )
    );

    is_deeply [@state], [], 'nonexistant';
}

# automatically stop once we get both new canonicals
my $canoncount = -2;
use Scalar::Util;
$replay->eventSystem->origin->subscribe(
    sub {
        my ($message) = @_;

        warn "This is a origin message of type " . $message->{MessageType} . "\n";
    }
);
$replay->eventSystem->derived->subscribe(
    sub {
        my ($message) = @_;

        warn "This is a derived message of type " . $message->{MessageType} . "\n";
    }
);
$replay->eventSystem->control->subscribe(
    sub {
        my ($message) = @_;

        my $json = new JSON;
        $json->canonical(1);
        use Data::Dumper;
        warn "This is a control message of type "
            . $message->{MessageType} . "\n";
        return unless $message->{MessageType} eq 'NewCanonical';
        $replay->eventSystem->stop unless ++$canoncount;
    }
);

my $time = gettimeofday;
$replay->eventSystem->run;


use Data::Dumper;
warn Dumper
my ($meta, @state) =   $replay->storageEngine->fetchCanonicalState(
        Replay::IdKey->new(
            { domain => 'basicmongotest', name => 'TESTRULE', version => 1, window => 'alltime', key => 'a' }
        )
    );
is_deeply [ @state ], [ 15 ];

is_deeply $replay->storageEngine->windowAll(
    Replay::IdKey->new(
        { domain => 'basicmongotest', name => 'TESTRULE', version => 1, window => 'alltime', key => 'a' }
    )
    ),
    { a => [15], c => [40] }, "windowall returns all";

LATTER:

my $idkey = Replay::IdKey->new(
    { domain => 'basicmongotest', name => 'TESTRULE', version => 1, window => 'alltime', key => 'x' });

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
        ok !$cuuid, 'failed while checkout already is proper';
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

warn "clearing collection "
    . $ourtestkey->collection
    . " in db "
    . $replay->storageEngine->engine->dbname()
    . " result is "
    . Dumper $replay->storageEngine->engine->collection($ourtestkey)
    ->drop({});


