package Replay::Message::Typical;
use Moose::Role;
use MooseX::MetaDescription::Meta::Trait;
with qw/Replay::Envelope/;
has key => (
    is          => 'ro',
    isa         => 'Str',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'message' },
);
has array => (
    is          => 'ro',
    isa         => 'ArrayRef[Int]',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'message' },
);

package Replay::Message::Interesting;
use Moose;
extends 'Replay::Message';
with qw/Replay::Message::Typical/;
has '+MessageType' => (default => 'Interesting');

package Replay::Message::Boring;
use Moose;
extends 'Replay::Message';
with qw/Replay::Message::Typical/;
has '+MessageType' => (default => 'Boring');

package TESTRULE;

use Replay::IdKey;
use Moose;
extends 'Replay::BusinessRule';
use List::Util qw//;
use Data::Dumper;

has '+name' => (default => __PACKAGE__,);

override match => sub {
    my ($self, $message) = @_;
    return $message->{MessageType} eq 'Interesting';
};

override keyValueSet => sub {
    my ($self, $message) = @_;
    my @keyvalues = ();
    next unless 'ARRAY' eq ref $message->{Message}{array};
    foreach (@{ $message->{Message}{array} }) {
        push @keyvalues, $message->{Message}->{key}, $_;
    }
    return @keyvalues;
};

override compare => sub {
    my ($self, $aa, $bb) = @_;
    return ($aa || 0) <=> ($bb || 0);
};

override delivery => sub {
    my ($self, $filehandle, $meta, @state) = @_;
    my $r = { output => $state[0] || 0 };
    warn "RULE DELIVERY $filehandle $meta @state " . YAML::Dump($r);
    print $filehandle YAML::Dump($r);
    return 1;
};

no warnings;

override reduce => sub {
    my ($self, $emitter, @state) = @_;
    my $response = List::Util::reduce { $a + $b } @state;
};

package ReplayReportFileTest;

use strict;
use warnings;

use base 'Test::Class';

use Test::Most;
use Replay::ReportEngine::Filesystem;
use Replay;
use Replay::RuleSource;
use Replay::EventSystem;
use Data::Dumper;
use POSIX;
use File::Slurp;
use Try::Tiny;

my $replay;
my $reportEngine;

sub A_store : Test(5) {
    isa_ok $reportEngine, 'Replay::ReportEngine::Filesystem';
    my $funMessage = Replay::Message::Interesting->new(
        key    => 'a',
        array  => [ 5, 1, 2, 3, 4 ],
        Domain => 'Testing'
    );
    my $notAfterAll = Replay::Message::Boring->new(
        key    => 'b',
        array  => [ 1, 2, 3, 4, 5, 6 ],
        Domain => 'Testing'
    );
    my $secondMessage = Replay::Message::Interesting->new(
        key    => 'c',
        array  => [ 6, 7, 8, 9, 10 ],
        Domain => 'Testing'
    );

    $replay->worm;
    $replay->reducer;
    $replay->mapper;

    #    $replay->clerk;

    $replay->eventSystem->origin->emit($funMessage);
    $replay->eventSystem->origin->emit($secondMessage);
    my $idkey = Replay::IdKey->new(
        domain  => 'Testing',
        name    => 'TESTRULE',
        version => 1,
        window  => 'alltime',
        key     => 'a'
    );
    my ($meta, $handle) = $reportEngine->deliver($idkey, 'latest');
    is_deeply $meta, { __EMPTY__ => 1 },
        'there is no meta data in the report yet';
    is_deeply [$handle], [undef], 'there is no data in the report yet';
    my $count = -4;
    $replay->eventSystem->control->subscribe(
        sub {
            my $message = shift;
            try {
                if ($message->{MessageType} eq 'NewDelivery') {
                    my $idkey = Replay::IdKey->new($message->{Message});
                    warn "MESSAGE TYPE: " . $message->{MessageType};
                    $reportEngine->set_latest($idkey, $message->{Message}->{revision});
                    ++$count;
                    warn "FOUND A NEW NEWDELIVERY ($count)";
                }
                if ($message->{MessageType} eq 'NewCanonical') {
                    my $idkey = Replay::IdKey->new($message->{Message});
                    warn "MESSAGE TYPE: " . $message->{MessageType};
                    $reportEngine->delivery($idkey);
                    ++$count;
                }
                $replay->eventSystem->stop unless $count;
            }

            catch {
                warn "Failure in custom clerk bit in test: $_";
            };
        }
    );
    $replay->eventSystem->run;
    {

        warn "FILES IN REPLAYREPORT\n" . `find /replayreport -type f`;
        warn "Trying to call deliver AGAIN";
        my ($meta, $handle) = $reportEngine->deliver($idkey);
        is_deeply $meta,
            {
            extension  => 'yaml',
            Windows    => 'alltime',
            Timeblocks => [strftime('%Y-%m-%d-%H', localtime time)],
            Ruleversions => [{rule => 'TESTRULE', version => 1}],
            type       => 'text/yaml'
            },
            'meta';
        is_deeply YAML::Load(do { local $/; <$handle> }), {output=>15},
            'there is now data in the report yet';
    }
    return;
}

sub B_Clerk : Test(5) {
    isa_ok $reportEngine, 'Replay::ReportEngine::Filesystem';
    my $funMessage = Replay::Message::Interesting->new(
        key    => 'a',
        array  => [ 5, 1, 2, 3, 4 ],
        Domain => 'Testing'
    );
    my $notAfterAll = Replay::Message::Boring->new(
        key    => 'b',
        array  => [ 1, 2, 3, 4, 5, 6 ],
        Domain => 'Testing'
    );
    my $secondMessage = Replay::Message::Interesting->new(
        key    => 'c',
        array  => [ 6, 7, 8, 9, 10 ],
        Domain => 'Testing'
    );

    $replay->worm;
    $replay->reducer;
    $replay->mapper;
    $replay->clerk;

    $replay->eventSystem->origin->emit($funMessage);
    $replay->eventSystem->origin->emit($secondMessage);
    my $idkey = Replay::IdKey->new(
        domain  => 'Testing',
        name    => 'TESTRULE',
        version => 1,
        window  => 'alltime',
        key     => 'a'
    );
    my ($meta, $handle) = $reportEngine->deliver($idkey, 'latest');
    is_deeply $meta, { __EMPTY__ => 1 },
        'there is no meta data in the report yet';
    is_deeply [$handle], [undef], 'there is no data in the report yet';
    my $count = -4;
    $replay->eventSystem->control->subscribe(
        sub {
            my $message = shift;
            try {
                if ($message->{MessageType} eq 'NewDelivery') {
                    my $idkey = Replay::IdKey->new($message->{Message});
                    warn "MESSAGE TYPE: " . $message->{MessageType};
                    $reportEngine->set_latest($idkey, $message->{Message}->{revision});
                    ++$count;
                    warn "FOUND A NEW NEWDELIVERY ($count)";
                }
                if ($message->{MessageType} eq 'NewCanonical') {
                    my $idkey = Replay::IdKey->new($message->{Message});
                    warn "MESSAGE TYPE: " . $message->{MessageType};
                    $reportEngine->delivery($idkey);
                    ++$count;
                }
                $replay->eventSystem->stop unless $count;
            }

            catch {
                warn "Failure in custom clerk bit in test: $_";
            };
        }
    );
    $replay->eventSystem->run;
    {

        warn "FILES IN REPLAYREPORT\n" . `find /replayreport -type f`;
        warn "Trying to call deliver AGAIN";
        my ($meta, $handle) = $reportEngine->deliver($idkey);
        is_deeply $meta,
            {
            extension  => 'yaml',
            Windows    => 'alltime',
            Timeblocks => [strftime('%Y-%m-%d-%H', localtime time)],
            Ruleversions => [{rule => 'TESTRULE', version => 1}],
            type       => 'text/yaml'
            },
            'meta';
        is_deeply YAML::Load(do { local $/; <$handle> }), {output=>15},
            'there is now data in the report yet';
    }
    return;
}

sub startup : Test(startup) {
}

sub setup : Test(setup) {
    $replay = Replay->new(
        config => {
            QueueClass     => 'Replay::EventSystem::Null',
            StorageMode    => 'Memory',
            ReportMode     => 'Filesystem',
            ReportFileRoot => '/replayreport',
            timeout        => 5,
            domain         => 'Testing',
            stage          => 'testscriptfilesystem-' . $ENV{USER},
        },
        rules => [ new TESTRULE ]
    );
    $reportEngine = $replay->reportEngine->engine;
    $replay->reportEngine->engine->drop;
}

sub teardown : Test(teardown) {
    $replay->reportEngine->engine->drop;
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
