package TESTRULE;

use Moose;
use Replay::Types;
use List::Util qw//;
use Data::Dumper;
use JSON qw/to_json/;
with 'Replay::Role::BusinessRule' => { -version => 0.02 };

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
    foreach my $key (keys %{ $message->{Message} }) {
        next unless 'ARRAY' eq ref $message->{Message}->{$key};
        foreach (@{ $message->{Message}->{$key} }) {
            push @keyvalues, $key, $_;
        }
    }
    return @keyvalues;
}

sub compare {
    my ($self, $aa, $bb) = @_;
    return 1 if $aa eq 'purge' || $bb eq 'purge';
    return ($aa || 0) <=> ($bb || 0);
}

sub reduce {
    my ($self, $emitter, @state) = @_;
    warn "PURGE FOUND" if grep { $_ eq 'purge' } @state;
    return if grep { $_ eq 'purge' } @state;
    return List::Util::reduce { $a + $b } @state;
}

sub delivery {
    my ($self, @state) = @_;
    return unless @state;
    warn "TESTRULE DELIVERY";
    return to_json [@state];
}

package Test::ReportModule;

use AnyEvent;
use Test::Most tests => 12;
use Data::Dumper;
use Net::RabbitMQ;
use Time::HiRes qw/gettimeofday/;
use JSON qw/to_json from_json/;

use_ok 'Replay';

my $storedir = '/tmp/testscript-07-' . $ENV{USER};
`rm -r $storedir`;

my $replay = Replay->new(
    config => {
        QueueClass           => 'Replay::EventSystem::Null',
        StorageMode          => 'Memory',
        ReportMode           => 'Filesystem',
        timeout              => 10,
        stage                => 'testscript-07-' . $ENV{USER},
        reportFilesystemRoot => $storedir,
    },
    rules => [ new TESTRULE ]
);

$replay->worm;
$replay->reducer;
$replay->mapper;
$replay->reporter;

my $engine = $replay->reportEngine;

isa_ok $engine, 'Replay::ReportEngine';

my $reporter = $engine->engine;

isa_ok $reporter, 'Replay::BaseReportEngine';

ok $reporter->can('delivery');
ok $reporter->can('summary');
ok $reporter->can('globsummary');
ok $reporter->can('freeze');

my $funMessage = { MessageType => 'interesting',
    Message => { a => [ 5, 1, 2, 3, 4 ], } };
my $notAfterAll
    = { MessageType => 'boring', Message => { b => [ 1, 2, 3, 4, 5, 6 ] } };
my $secondMessage = { MessageType => 'interesting',
    Message => { c => [ 6, 7, 8, 9, 10 ], } };

my $purgeMessage = { MessageType => 'interesting',
    Message => { c => [ 'purge' ], } };

# automatically stop once we get both new canonicals
my $canoncount = -2;
my $deliverycount = -2;
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

        return if $message->{MessageType} eq 'Fetched';
        warn __FILE__
            . ": This is a control message of type "
            . $message->{MessageType} . "\n";

        #        return unless $message->{MessageType} eq 'NewCanonical';
        return unless $message->{MessageType} eq 'ReportNewDelivery';
        return if ++$canoncount;
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

        is_deeply [
            $replay->reportEngine->delivery(
                Replay::IdKey->new(
                    { name => 'TESTRULE', version => 1, window => 'alltime', key => 'a' }
                )
            )
            ],
            ['["15"]'];

        $replay->eventSystem->control->subscribe(
            sub {
                my ($message) = @_;

                return if $message->{MessageType} eq 'Fetched';
                warn __FILE__
                    . ": This is a control message of type "
                    . $message->{MessageType} . "\n";

                return unless $message->{MessageType} eq 'ReportNewDelivery';
                return if ++ $deliverycount;

                warn "PROPER STOP";
                $replay->eventSystem->stop;
            }
        );

        $replay->eventSystem->derived->emit($funMessage);
        $replay->eventSystem->derived->emit($purgeMessage);
    }
);

my $time = gettimeofday;

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
    $replay->reportEngine->delivery(
        Replay::IdKey->new(
            { name => 'TESTRULE', version => 1, window => 'alltime', key => 'a' }
        )
    )
    ],
    ['["30"]'], 'doubled on extra insert';

is_deeply [
    $replay->reportEngine->delivery(
        Replay::IdKey->new(
            { name => 'TESTRULE', version => 1, window => 'alltime', key => 'c' }
        )
    )
    ],
    [], 'purged data returns empty serialization';





