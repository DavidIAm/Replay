#
# Testing class for Replay module components

=pod

package BasicReplayTest;

use base qw/Test::Replay/;

sub getreplay : Test(setup) {
    my $self   = shift;
    my $replay = Replay->new(
        config => {
            EventSystem   => { Mode => 'Null' },
            StorageEngine => { Mode => 'Memory' },
            timeout       => 50,
            stage         => 'testscript-01-' . $ENV{USER},
        },
        rules => [ new TESTRULE ]
    );

    $replay->worm;
    $replay->reducer;
    $replay->mapper;
    $replay->reporter;

    $self->{replay} = $replay;
}

sub done_now : Test(teardown) {
    my $self = shift;
    my $replay = $self->{replay};

        # nothing to do for null and memory
}

Test::Class->runtests();

=cut

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
    warn __FILE__ . ": KEYVALUESET HIT" . to_json [@keyvalues]
        if $ENV{DEBUG_REPLAY_TEST};
    return @keyvalues;
}

sub compare {
    my ($self, $aa, $bb) = @_;
    return 1 if $aa eq 'purge' || $bb eq 'purge';
    return ($aa || 0) <=> ($bb || 0);
}

sub reduce {
    my ($self, $emitter, @state) = @_;
    warn __FILE__ . ": REDUCE HIT" . to_json [@state] if $ENV{DEBUG_REPLAY_TEST};
    warn __FILE__ . ": PURGE FOUND"
        if grep { $_ eq 'purge' }
        grep { defined $_ } @state && $ENV{DEBUG_REPLAY_TEST};
    return if grep { $_ eq 'purge' } grep { defined $_ } @state;
    return List::Util::reduce { $a + $b } @state;
}

sub delivery {
    my ($self, @state) = @_;
    use Data::Dumper;
    warn __FILE__ . ": DELIVERY HIT" . to_json [@state]
        if $ENV{DEBUG_REPLAY_TEST};
    return [ map { $_ . '' } @state ], to_json [@state];
}

sub summary {
    my ($self, %deliverydatas) = @_;
    my @state
        = map { $_ . '' }
        keys %deliverydatas
        ? List::Util::reduce { $a + $b }
    map { @{ $deliverydatas{$_} } } keys %deliverydatas
        : ();
    warn __FILE__ . ": SUMMARY HIT" . to_json [@state] if $ENV{DEBUG_REPLAY_TEST};
    return [@state], to_json [@state];
}

sub globsummary {
    my ($self, %summarydatas) = @_;
    my @state
        = map { $_ . '' }
        keys %summarydatas
        ? List::Util::reduce { $a + $b }
    map { @{ $summarydatas{$_} } } keys %summarydatas
        : ();
    warn __FILE__ . ": GLOBSUMMARY HIT" . to_json [@state]
        if $ENV{DEBUG_REPLAY_TEST};
    return [@state], to_json [@state];
}

package EMPTYREPORTDATA;

use Moose;
extends qw(TESTRULE);

has '+name' => (default => __PACKAGE__,);

sub delivery {
    return [], 'dog';
}

sub summary {
    return [];
}

sub globsummary {
    return [];
}

package Replay::Test;

use base qw(Test::Class);

use Data::Dumper;
use AnyEvent;
use Test::Most;
use Data::Dumper;
use Net::RabbitMQ;
use Time::HiRes qw/gettimeofday/;
use JSON qw/to_json from_json/;

sub a_message : Test(setup) {
    my $self = shift;

    # These are the messages structures we're going to work with
    $self->{funMessage} = { MessageType => 'interesting',
        Message => { a => [ 5, 1, 2, 3, 4 ], } };
    $self->{notAfterAll}
        = { MessageType => 'boring', Message => { b => [ 1, 2, 3, 4, 5, 6 ] } };
    $self->{secondMessage} = { MessageType => 'interesting',
        Message => { c => [ 6, 7, 8, 9, 10 ], } };

    $self->{lateMessage} = {
        MessageType => 'interesting',
        Message     => { t => [ 10, 20, 30, 40, 50 ], }
    };

    $self->{purgeMessage}
        = { MessageType => 'interesting', Message => { c => ['purge'], } };

}

sub a_testruleoperation : Test(no_plan) {
    my $self = shift;

    # first some sanity checking for the TESTRULE to make sure we got it right
    my $rule = new TESTRULE;

    # match has only two ways
    ok $rule->match($self->{funMessage}), 'interesting';
    ok !$rule->match($self->{notAfterAll}), 'boring';

    # window as expected for each message
    is $rule->window($self->{funMessage}),    'early';
    is $rule->window($self->{secondMessage}), 'early';
    is $rule->window($self->{lateMessage}),   'late';

    # corner cases for window
    is $rule->window({ Message => { M   => undef } }), 'early', 'window early';
    is $rule->window({ Message => { N   => undef } }), 'late',  'window late';
    is $rule->window({ Message => { '%' => undef } }), 'late',  'window late';
    is_deeply [ $rule->key_value_set($self->{funMessage}) ],
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
        [ [15], '["15"]' ], 'summary verify';
    is_deeply [ $rule->globsummary() ], [ [], '[]' ], 'globsummary verify empty';
    is_deeply [
        $rule->globsummary(f => [5], g => [4], h => [3], i => [2], j => [1]) ],
        [ [15], '["15"]' ], 'summary verify';

}

sub m_replay_construct : Test(startup => 2) {
    warn "REPLAY CONSTRUCT" if $ENV{DEBUG_REPLAY_TEST};
    my $self = shift;
    return "out of replay context" unless defined $self->{config};

    use_ok 'Replay';

    ok defined(
        $self->{replay} = Replay->new(
            config => $self->{config},
            rules  => [ new TESTRULE, new EMPTYREPORTDATA ]
        )
    );

}

sub y_replay_initialize : Test(startup => 1) {
    warn "REPLAY INITIALIZE" if $ENV{DEBUG_REPLAY_TEST};
    my $self = shift;
    return "out of replay context" unless defined $self->{config};
    ok $self->{replay}, 'have replay';
    my $replay = $self->{replay};
    $replay->worm;
    $replay->reducer;
    $replay->mapper;
    $replay->reporter;
}

sub r_testreporter : Test(6) {
    my $self   = shift;
    my $replay = $self->{replay};
    return "out of replay context" unless $replay;
    ok $self->{replay}, 'have replay';
    my $engine = $replay->reportEngine;

    isa_ok $engine, 'Replay::ReportEngine';

    my $reporter
        = $engine->engine(Replay::IdKey->new(name => 'TESTRULE', version => 1));

    $reporter->does('Replay::Role::ReportEngine');

    ok $reporter->can('delivery'),    'api check delivery';
    ok $reporter->can('summary'),     'api check summary';
    ok $reporter->can('globsummary'), 'api check globsummary';
    ok $reporter->can('freeze'),      'api check freeze';
}

sub c_testworm : Test(no_plan) {
    my $self   = shift;
    my $replay = $self->{replay};
    return "out of replay context" unless $replay;
}

sub e_testreducer : Test(no_plan) {
    my $self   = shift;
    my $replay = $self->{replay};
    return "out of replay context" unless $replay;
}

sub d_testmapper : Test(no_plan) {
    my $self   = shift;
    my $replay = $self->{replay};
    return "out of replay context" unless $replay;
}

sub f_teststorage : Test(no_plan) {
    my $self   = shift;
    my $replay = $self->{replay};
    return "out of replay context" unless $replay;
}

sub m_testloop : Test(8) {
    my $self   = shift;
    my $replay = $self->{replay};
    return "out of replay context" unless defined $self->{config};
    ok $self->{replay}, 'have replay';

    # automatically stop once we get both new canonicals
    my $globsumcount    = -6;
    my $secglobsumcount = -1;
    $self->{purgecount} = -2;

    # We regulate our operations by watching the control channel
    # Once we know the proper things have happened we can emit
    # more or stop the test.
    $self->{keyA} = Replay::IdKey->new(
        { name => 'TESTRULE', version => 1, window => 'early', key => 'a' });
    $self->{keyC} = Replay::IdKey->new(
        { name => 'TESTRULE', version => 1, window => 'early', key => 'c' });
    $self->{keyT} = Replay::IdKey->new(
        { name => 'TESTRULE', version => 1, window => 'late', key => 't' });
    $self->{keyX} = Replay::IdKey->new(
        { name => 'TESTRULE', version => 1, window => 'late', key => 'x' });

    my $ee; # scope for loop terminator timer;
    $replay->eventSystem->control->subscribe(
        sub {
            my ($message) = @_;

            #This just suppresses noise, because there are many fetches
            return if $message->{MessageType} eq 'Fetched';

            # so the tester can watch them fly by
            #            warn __FILE__
            #                . ": This is a control message of type "
            #                . $message->{MessageType} . "\n";

            # The behavior of this return plus the globsumcount increment is that
            # it will keep letting things run until it sees the third
            # ReportNewGlobSummary message
            return unless $message->{MessageType} eq 'ReportNewGlobSummary';
            return if ++$globsumcount;

            # Assertions for our middle of running state.
            # Is the canonical state as expected for the key a?
            is_deeply [ $replay->storageEngine->fetch_canonical_state($self->{keyA}) ],
                [15];

            # Is the canonical state as expected for the window early?
            is_deeply $replay->storageEngine->window_all($self->{keyA}),
                { a => [15], c => [40] }, "windowall returns all early";

            # Is the canonical state as expected for the window late?
            is_deeply $replay->storageEngine->window_all($self->{keyT}), { t => [150] },
                "windowall returns all late";

            # Get a pointer to a report that does not exist, and see that it does not.
            is_deeply [ $replay->reportEngine->delivery($self->{keyX}) ],
                [ { EMPTY => 1 } ], "X report proper";

            # Get a report for key a
            is_deeply [ $replay->reportEngine->delivery($self->{keyA}) ],
                [ { FORMATTED => '["15"]', EMPTY => 0 } ], "A delivery proper";

            # Get a formatted summary for window early
            # (the key part is ignored in this idkey!)
            is_deeply [ $replay->reportEngine->summary($self->{keyA}) ],
                [ { FORMATTED => '["55"]', EMPTY => 0 } ], "A summary proper";

            my $once = -1;
            $replay->eventSystem->control->subscribe(
                sub {
                    my ($message) = @_;

                    return                if $message->{MessageType} eq 'Fetched';
                    $self->{purgecount}++ if $message->{MessageType} eq 'ReportPurgedDelivery';
                    $secglobsumcount++    if $message->{MessageType} eq 'ReportNewGlobSummary';
                    return                if $secglobsumcount;
                    return                if $self->{purgecount};

                    warn __FILE__ . ": PROPER STOP ( $secglobsumcount, $self->{purgecount} )"
                        if $ENV{DEBUG_REPLAY_TEST};

                    # shut down the system in one second
                    return if ++$once;
                    ok 1, "EVENT SYSTEM STOP GOOD " . $message->{MessageType};

                    $ee = AnyEvent->timer(
                        after => 1,
                        cb    => sub {
                            $replay->eventSystem->stop;
                        }
                    );
                }
            );

            $replay->eventSystem->derived->emit($self->{funMessage});
            $replay->eventSystem->derived->emit($self->{purgeMessage});
        }
    );

    my $time = gettimeofday;

    my $e = AnyEvent->timer(
        after => 1,
        cb    => sub {
            $replay->eventSystem->derived->emit($self->{funMessage});
            $replay->eventSystem->derived->emit($self->{secondMessage});
            $replay->eventSystem->derived->emit($self->{lateMessage});
        }
    );

    $replay->eventSystem->run;

    ok $globsumcount >= 0, 'exit condition initial ' . $globsumcount;
    ok $secglobsumcount >= 0, 'exit condition second ' . $secglobsumcount;
    ok $self->{purgecount} >= 0, 'exit condition cseond ' . $self->purgecount;
}

sub n_testloop_report : Test(10) {
    my $self = shift;

    my $replay = $self->{replay};
    return "out of replay context" unless defined $self->{config};
    ok $self->{replay}, 'have replay';

    is $self->{purgecount}, 0,
        "we did get a purge when expected $self->{purgecount}";

    is_deeply [ $replay->reportEngine->delivery_data($self->{keyA}) ],
        [ { DATA => ["30"], EMPTY => 0 } ], 'data doubled on extra insert';

    is_deeply [ $replay->reportEngine->delivery_data($self->{keyC}) ],
        [ { EMPTY => 1 } ], 'purged data returns empty serialization';

    is_deeply [ $replay->reportEngine->summary_data($self->{keyT}) ],
        [ { EMPTY => 0, DATA => ["150"] } ], 'data expected summary';

    is_deeply [ $replay->reportEngine->globsummary_data($self->{keyT}) ],
        [ { EMPTY => 0, DATA => ["180"] } ], 'data expected globsummary';

    is_deeply [ $replay->reportEngine->delivery($self->{keyA}) ],
        [ { FORMATTED => '["30"]', EMPTY => 0 } ], 'doubled on extra insert';

    is_deeply [ $replay->reportEngine->delivery($self->{keyC}) ],
        [ { EMPTY => 1 } ], 'purged data returns empty serialization';

    is_deeply [ $replay->reportEngine->summary($self->{keyT}) ],
        [ { EMPTY => 0, FORMATTED => '["150"]' } ], 'expected summary';

    is_deeply [ $replay->reportEngine->globsummary($self->{keyT}) ],
        [ { EMPTY => 0, FORMATTED => '["180"]' } ], 'expected globsummary';

}

sub o_testloop_report_empty : Test(9) {
    my $self   = shift;
    my $replay = $self->{replay};
    return "out of replay context" unless defined $self->{config};
    ok $self->{replay}, 'have replay';

    $self->{keyEC} = Replay::IdKey->new(
        { name => 'EMPTYREPORTDATA', version => 1, window => 'early', key => 'c' });
    $self->{keyET} = Replay::IdKey->new(
        { name => 'EMPTYREPORTDATA', version => 1, window => 'early', key => 't' });
    $self->{keyEA} = Replay::IdKey->new(
        { name => 'EMPTYREPORTDATA', version => 1, window => 'early', key => 'a' });

    is_deeply [ my $e = $replay->reportEngine->delivery_data($self->{keyEA}) ],
        [ { EMPTY => 1 } ], 'empty because no data saved';

    is_deeply [ $replay->reportEngine->delivery_data($self->{keyEC}) ],
        [ { EMPTY => 1 } ], 'purged data returns empty serialization';

    is_deeply [ $replay->reportEngine->summary_data($self->{keyET}) ],
        [ { EMPTY => 1 } ], 'expected no summary';

    is_deeply [ $replay->reportEngine->globsummary_data($self->{keyET}) ],
        [ { EMPTY => 1 } ], 'expected no globsummary';

    is_deeply [ $replay->reportEngine->delivery($self->{keyEA}) ],
        [ { FORMATTED => 'dog', EMPTY => 0 } ], 'doubled on extra insert';

    is_deeply [ $replay->reportEngine->delivery($self->{keyEC}) ],
        [ { EMPTY => 1 } ], 'purged data returns empty serialization';

    is_deeply [ $replay->reportEngine->summary($self->{keyET}) ],
        [ { EMPTY => 1 } ], 'expected no summary';

    is_deeply [ $replay->reportEngine->globsummary($self->{keyET}) ],
        [ { EMPTY => 1 } ], 'expected no globsummary';

}

1;
