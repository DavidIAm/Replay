package TESTRULE;

use Replay::BusinessRule;
use Replay::IdKey;
use Moose;
extends 'Replay::BusinessRule';
use List::Util qw//;
use Data::Dumper;

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

override delivery => sub {
    my ($self, $meta, @state) = @_;
    warn "THIS IS DELIVERY";
    warn Dumper @state;
    return $state[0] + 0;
};

no warnings;

override reduce => sub {
    my ($self, $emitter, @state) = @_;
    my $response = List::Util::reduce { $a + $b } @state;
};

package ReplayReportGitTest;

use strict;
use warnings;

use base 'Test::Class';

use Test::Most;
use Replay::ReportEngine::Git;
use Replay;
use Replay::RuleSource;
use Replay::EventSystem;

my $replay;
my $reportEngine;

sub A_store : Test(1) {
    isa_ok $reportEngine, 'Replay::BaseReportEngine';
    my $funMessage
        = { Message => { a => [ 5, 1, 2, 3, 4 ] }, MessageType => 'interesting' };
    my $notAfterAll
        = { MessageType => 'Boring', Message => { b => [ 1, 2, 3, 4, 5, 6 ] } };
    my $secondMessage = { Message => { c => [ 6, 7, 8, 9, 10 ] },
        MessageType => 'interesting' };

    $replay->worm;
    $replay->reducer;
    $replay->mapper;

    $replay->eventSystem->derived->emit($funMessage);
    $replay->eventSystem->derived->emit($secondMessage);
    my $idkey = Replay::IdKey->new(
        name    => 'TESTRULE',
        version => 1,
        window  => 'alltime',
        key     => 'a'
    );
    is_deeply [ $reportEngine->delivery($idkey) ], [0], 'there is no data in the report yet';
    my $count = -2;
    $replay->eventSystem->control->subscribe(
        sub {
            $replay->eventSystem->stop unless ++$count;
        }
    );
		$replay->eventSystem->run;
    is_deeply $reportEngine->delivery($idkey), 15;
}

sub startup : Test(startup) {
}

sub setup : Test(setup) {
    $replay = Replay->new(
        config => {
            QueueClass  => 'Replay::EventSystem::Null',
            StorageMode => 'Memory',
            ReportMode  => 'Git',
            timeout     => 5,
            stage       => 'testscriptgit-' . $ENV{USER},
        },
        rules => [ new TESTRULE ]
    );
    $reportEngine = $replay->reportEngine->engine;
}

sub teardown : Test(teardown) {
    undef $reportEngine;
    undef $replay;
}

sub shutdown : Test(shutdown) {
}

__PACKAGE__->runtests;

__END__

my $replay = Replay->new(
    config => {
        QueueClass  => 'Replay::EventSystem::Null',
        StorageMode => 'Memory',
        timeout     => 5,
        stage       => 'testscript-' . $ENV{USER},
    },
    rules => [ new TESTRULE ]
);

my $re = $replay->reportEngine;
 = Replay::ReportEngine::Git->new(
