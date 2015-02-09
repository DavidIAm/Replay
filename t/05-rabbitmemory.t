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

override key_value_set => sub {
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

use Replay 0.02;
use Time::HiRes qw/gettimeofday/;
use Test::Most tests => 15;
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

my $replay = Replay->new(
    config => {
        stage       => 'tests',
        EventSystem => {
            Mode     => 'RabbitMQ',
            RabbitMQ => {
                host    => 'localhost',
                options => {
                    port     => '5672',
                    user     => 'testuser',
                    password => 'testpass',

                    #            user    => 'replay',
                    #            pass    => 'replaypass',
                    #vhost   => 'replay',
                    vhost       => '/testing',
                    timeout     => 30,
                    tls         => 1,
                    heartbeat   => 1,
                    channel_max => 0,
                    frame_max   => 131072
                },
            },
        },
        StorageEngine => { Mode => 'Memory' },
    },
    rules => [ new TESTRULE ]
);
my $ourtestkey = Replay::IdKey->new(
    { name => 'TESTRULE', version => 1, window => 'alltime', key => 'a' });

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
my $z = AnyEvent->timer(
    after => 20,
    cb    => sub {
        warn "SHUTDOWN TIMEOUT";
        $replay->eventSystem->stop;
      },
);
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

# Manually set up an expired record
my $signature = $replay->storageEngine->engine->state_signature($idkey, ['notreallylocked']);
$replay->storageEngine->engine->collection($idkey)->{ idkey => $idkey->cubby }{locked} = $signature;
$replay->storageEngine->engine->collection($idkey)->{ idkey => $idkey->cubby }{lockExpireEpoch} = time - 50000;

{
    my ($uuid, $dog) = $replay->storageEngine->engine->checkout($idkey, 5);
    ok $uuid, "able to check out block";

    ok ! scalar(%{$replay->storageEngine->engine->collection($idkey)} = ()), "removed entry ";
}

{
    $replay->storageEngine->engine->{debug} = 1;
    $Replay::StorageEngine::Memory::store = {};
    my ($buuid, $dog) = $replay->storageEngine->engine->checkout($idkey, 5);
    ok $buuid, 'checkout good';
    use Data::Dumper;
    warn "CHeked out ".$dog;

    {
        my ($cuuid, $dog) = $replay->storageEngine->engine->checkout($idkey, 5);
        ok !$cuuid, 'failed while checkout already proper';
    }

    ok $replay->storageEngine->engine->revert($idkey, $buuid), "revert clean";
    $replay->storageEngine->engine->{debug} = 0;
}

{
    my ($uuid, $dog) = $replay->storageEngine->engine->checkout($idkey, 5);
    ok $uuid, "checked out for error cause";
}

# cleanup
$replay->eventSystem->clear;

