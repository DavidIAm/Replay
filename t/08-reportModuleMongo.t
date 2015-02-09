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
    return 'early'
        if substr((keys %{ $message->{Message} })[0], 0, 1) =~ /[abcdefghijklm]/i;
    return 'late';
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
    warn __FILE__ . ": PURGE FOUND" if grep { $_ eq 'purge' } @state;
    return                          if grep { $_ eq 'purge' } @state;
    return List::Util::reduce { $a + $b } @state;
}

sub delivery {
    my ($self, @state) = @_;
    use Data::Dumper;
    warn __FILE__ . ": DELIVERY HIT";
    return [@state], to_json [@state];
}

sub summary {
    my ($self, %deliverydatas) = @_;
    warn __FILE__ . ": SUMMARY HIT";
    my @state
        = keys %deliverydatas
        ? List::Util::reduce { $a + $b }
    map { @{ $deliverydatas{$_} } } keys %deliverydatas
        : ();
    return [@state], to_json [@state];
}

sub globsummary {
    my ($self, %summarydatas) = @_;
    warn __FILE__ . ": GLOBSUMMARY HIT";
    my @state
        = keys %summarydatas
        ? List::Util::reduce { $a + $b }
    map { @{ $summarydatas{$_} } } keys %summarydatas
        : ();
    return [@state], to_json [@state];
}

package Test::ReportModule;

use AnyEvent;
use Test::Most tests => 47;
use Data::Dumper;
use Net::RabbitMQ;
use Time::HiRes qw/gettimeofday/;
use JSON qw/to_json from_json/;

# These are the messages structures we're going to work with
my $funMessage = { MessageType => 'interesting',
    Message => { a => [ 5, 1, 2, 3, 4 ], } };
my $notAfterAll
    = { MessageType => 'boring', Message => { b => [ 1, 2, 3, 4, 5, 6 ] } };
my $secondMessage = { MessageType => 'interesting',
    Message => { c => [ 6, 7, 8, 9, 10 ], } };

my $lateMessage = {
    MessageType => 'interesting',
    Message     => { t => [ 10, 20, 30, 40, 50 ], }
};

my $purgeMessage
    = { MessageType => 'interesting', Message => { c => ['purge'], } };

# first some sanity checking for the TESTRULE to make sure we got it right
my $rule = new TESTRULE;

# match has only two ways
ok $rule->match($funMessage), 'interesting';
ok !$rule->match($notAfterAll), 'boring';

# window as expected for each message
is $rule->window($funMessage),    'early';
is $rule->window($secondMessage), 'early';
is $rule->window($lateMessage),   'late';

# corner cases for window
is $rule->window({ Message => { M   => undef } }), 'early', 'window early';
is $rule->window({ Message => { N   => undef } }), 'late',  'window late';
is $rule->window({ Message => { '%' => undef } }), 'late',  'window late';
is_deeply [ $rule->key_value_set($funMessage) ],
    [ a => 5, a => 1, a => 2, a => 3, a => 4, ], 'key value set expansion';
is $rule->compare(0,       0),       0,  'compare permute';
is $rule->compare(1,       0),       1,  'compare permute';
is $rule->compare(-1,      0),       -1, 'compare permute';
is $rule->compare(0,       1),       -1, 'compare permute';
is $rule->compare(1,       1),       0,  'compare permute';
is $rule->compare(-1,      1),       -1, 'compare permute';
is $rule->compare(0,       -1),      1,  'compare permute';
is $rule->compare(1,       -1),      1,  'compare permute';
is $rule->compare(-1,      -1),      0,  'compare permute';
is $rule->compare(-1,      'purge'), 1,  'compare permute';
is $rule->compare(0,       'purge'), 1,  'compare permute';
is $rule->compare(1,       'purge'), 1,  'compare permute';
is $rule->compare('purge', -1),      1,  'compare permute';
is $rule->compare('purge', 0),       1,  'compare permute';
is $rule->compare('purge', 1),       1,  'compare permute';

is $rule->reduce(undef, qw[1 2 3 4 5]),    15, 'reduce verify';
is $rule->reduce(undef, qw[1 2 3 4 5 10]), 25, 'reduce verify';

is_deeply [ $rule->summary() ], [ [], '[]' ], 'summary verify empty';
is_deeply [
    $rule->summary(a => [5], b => [4], c => [3], d => [2], e => [1]) ],
    [ [15], '[15]' ], 'summary verify';
is_deeply [ $rule->globsummary() ], [ [], '[]' ], 'globsummary verify empty';
is_deeply [
    $rule->globsummary(f => [5], g => [4], h => [3], i => [2], j => [1]) ],
    [ [15], '[15]' ], 'summary verify';

use_ok 'Replay';

my $replay = Replay->new(
    config => {
        EventSystem   => { Mode => 'Null', },
        StorageEngine => { Mode => 'Memory', },
        ReportEngine  => {
            Mode      => 'Mongo',
            MongoUser => 'replayuser',
            MongoPass => 'replaypass',
        },
        timeout => 10,
        stage   => 'testscript-08-' . $ENV{USER},
    },
    rules => [ new TESTRULE ]
);

$replay->reportEngine->engine->collection(
    Replay::IdKey->new(name => 'TESTRULE', version => 1))->remove();

$replay->worm;
$replay->reducer;
$replay->mapper;
$replay->reporter;

my $engine = $replay->reportEngine;

isa_ok $engine, 'Replay::ReportEngine';

my $reporter = $engine->engine;

$reporter->does('Replay::BaseReportEngine');

ok $reporter->can('delivery'),    'api check delivery';
ok $reporter->can('summary'),     'api check summary';
ok $reporter->can('globsummary'), 'api check globsummary';
ok $reporter->can('freeze'),      'api check freeze';

# automatically stop once we get both new canonicals
my $globsumcount    = -3;
my $secglobsumcount = -2;
my $purgecount      = 0;
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

# We regulate our operations by watching the control channel
# Once we know the proper things have happened we can emit
# more or stop the test.
my $keyA = Replay::IdKey->new(
    { name => 'TESTRULE', version => 1, window => 'early', key => 'a' });
my $keyC = Replay::IdKey->new(
    { name => 'TESTRULE', version => 1, window => 'early', key => 'c' });
my $keyT = Replay::IdKey->new(
    { name => 'TESTRULE', version => 1, window => 'late', key => 't' });
my $keyX = Replay::IdKey->new(
    { name => 'TESTRULE', version => 1, window => 'late', key => 'x' });
$replay->eventSystem->control->subscribe(
    sub {
        my ($message) = @_;

        #This just suppresses noise, because there are many fetches
        return if $message->{MessageType} eq 'Fetched';

        # so the tester can watch them fly by
        warn __FILE__
            . ": This is a control message of type "
            . $message->{MessageType} . "\n";

        # The behavior of this return plus the globsumcount increment is that
        # it will keep letting things run until it sees the third
        # ReportNewGlobSummary message
        return unless $message->{MessageType} eq 'ReportNewGlobSummary';
        return if ++$globsumcount;

        # Assertions for our middle of running state.
        # Is the canonical state as expected for the key a?
        is_deeply [ $replay->storageEngine->fetch_canonical_state($keyA) ], [15];

        # Is the canonical state as expected for the window early?
        is_deeply $replay->storageEngine->window_all($keyA),
            { a => [15], c => [40] }, "windowall returns all early";

        # Is the canonical state as expected for the window late?
        is_deeply $replay->storageEngine->window_all($keyT), { t => [150] },
            "windowall returns all late";

        # Get a pointer to a report that does not exist, and see that it does not.
        is_deeply [ $replay->reportEngine->delivery($keyX) ], [ { EMPTY => 1 } ];

        # Get a report for key a
        is_deeply [ $replay->reportEngine->delivery($keyA) ],
            [ { FORMATTED => '["15"]', EMPTY => 0 } ];

        # Get a formatted summary for window early
        # (the key part is ignored in this idkey!)
        is_deeply [ $replay->reportEngine->summary($keyA) ],
            [ { FORMATTED => '[55]', EMPTY => 0 } ];

        $replay->eventSystem->control->subscribe(
            sub {
                my ($message) = @_;

                return             if $message->{MessageType} eq 'Fetched';
                $purgecount++      if $message->{MessageType} eq 'ReportPurgedDelivery';
                $secglobsumcount++ if $message->{MessageType} eq 'ReportNewGlobSummary';
                return             if $secglobsumcount;

                warn __FILE__ . ": PROPER STOP";
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
        $replay->eventSystem->derived->emit($lateMessage);
    }
);

$replay->eventSystem->run;

ok $purgecount, "we did get a purge when expected";

is_deeply [ $replay->reportEngine->delivery($keyA) ],
    [ { FORMATTED => '["30"]', EMPTY => 0 } ], 'doubled on extra insert';

is_deeply [ $replay->reportEngine->delivery($keyC) ], [ { EMPTY => 1 } ],
    'purged data returns empty serialization';

is_deeply [ $replay->reportEngine->summary($keyT) ],
    [ { EMPTY => 0, FORMATTED => '["150"]' } ], 'expected summary';
is_deeply [ $replay->reportEngine->globsummary($keyT) ],
    [ { EMPTY => 0, FORMATTED => '[180]' } ], 'expected globsummary';

