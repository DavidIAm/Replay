#!/usr/bin/perl

use lib 'Replay/lib/';

package TESTRULE;
use Data::Dumper;

use Replay::BusinessRule;
use Replay::IdKey;
use Moose;
extends 'Replay::BusinessRule';
use List::Util qw//;

has '+name' => (default => __PACKAGE__,);

override match => sub {
    my ($self, $message) = @_;
#    return $message->{type} eq 'CargoTelRequest';
    return $message->{is_interesting};
};

#override window => sub {
#    my ($self, $message) = @_;
##    return $message->{window} if $message->{window};
#    return super;
#};

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
    my ($self, @state) = @_;
    return List::Util::reduce { $a + $b } @state;
#    my @outstate = ();
#    foreach my $message (@state) {
#        my $result = $EDI->$message->process();
#        if ($result->is_success) {
#            $self->emit("ThisWasASuccessMessage", CRMACTION);
#        }
#        else {
#            # didn't work, save for later
#            $self->emit("CRMCREATEREQUESTFAIL", $result);
#            push @outstate,
#                $message->augment(resultlist => [ time => time, result => $result ]);
#        }
#    }
#    return @outstate

};

package main;
use Data::Dumper;

use Replay::EventSystem;
use Replay::RuleSource;
use Replay::StorageEngine;
use Replay::Reducer;
use Replay::Mapper;
use Time::HiRes qw/gettimeofday/;
use Test::Most;
use CgtConfig;
use JSON;

# test the event transition interface

# an event transition has a match/map

my $locale = CgtConfig::locale('test');

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

my $funMessage = { a => [ 5, 1, 2, 3, 4 ], is_interesting => 1 };
my $notAfterAll = { b => [ 1, 2, 3, 4, 5, 6 ] };
my $secondMessage = { c => [ 6, 7, 8, 9, 10 ], is_interesting => 1 };

is_deeply [ $tr->keyValueSet($funMessage) ],
    [ a => 5, a => 1, a => 2, a => 3, a => 4 ], 'expands';

is_deeply [ $tr->keyValueSet({ b => [ 1, 2, 3, 4 ] }) ],
    [ b => 1, b => 2, b => 3, b => 4 ];

my $eventSystem = Replay::EventSystem->new(timeout => 30, locale => $locale);
my $ruleSource = Replay::RuleSource->new(
    rules       => [ new TESTRULE ],
    eventSystem => $eventSystem
);
my $storage = Replay::StorageEngine->new(
		mode => 'Mongo',
		locale => $locale,
    ruleSource  => $ruleSource,
    eventSystem => $eventSystem
);
my $reducer = Replay::Reducer->new(
    eventSystem   => $eventSystem,
    ruleSource    => $ruleSource,
    storageEngine => $storage
);
my $mapper = Replay::Mapper->new(
    ruleSource  => $ruleSource,
    eventSystem => $eventSystem,
    storageSink => $storage,
);

$eventSystem->poll;

$eventSystem->derived->emit(to_json $funMessage);
$eventSystem->derived->emit(to_json $secondMessage);

is_deeply [
    $storage->fetchCanonicalState(
        Replay::IdKey->new({ name => 'TESTRULE', version => 1, window => 'alltime', key => 'a' })
    )
    ],
    [], 'nonexistant';

		# automatically stop once we get both new canonicals
my $canoncount = -2;
use Scalar::Util;
$eventSystem->control->subscribe(sub {
		my ($message) = @_;
		warn "This is a control message of type ".$message->messageType." looking for 'NewCanonical'\n";
		return unless blessed $message;
		return unless $message->messageType eq 'NewCanonical';
		$eventSystem->stop unless ++$canoncount;
		warn "NewCanonical countup $canoncount";
	});

		warn "STARTING RUN";
		my $time = gettimeofday;
$eventSystem->run;
		warn "ENDING RUN";
		warn "ELAPSED DURING RUN WAS: " . (gettimeofday-$time) . "\n";

is_deeply [
    $storage->fetchCanonicalState(
        Replay::IdKey->new({ name => 'TESTRULE', version => 1, window => 'alltime', key => 'a' })
    )
    ],
    [15];

use Data::Dumper;
print Dumper $storage->windowAll(Replay::IdKey->new({ name => 'TESTRULE', version => 1, window => 'alltime', key => 'a' }));

done_testing();

__END__
package FTPReader;

use Replay::BusinessRule;
use Moose;
extends 'Replay::BusinessRule';
use List::Util qw//;

has '+name' => (default => __PACKAGE__,);

override match => sub {
    my ($self, $message) = @_;
    return $message->{type} eq 'Timing' && $message->{OnTheFive};
};

#override window => sub {
#    my ($self, $message) = @_;
##    return $message->{window} if $message->{window};
#    return super;
#};

override keyValueSet => sub {
    my ($self, $message) = @_;
    return $message
};

override compare => sub {
    my ($self, $aa, $bb) = @_;
    return ($aa || 0) <=> ($bb || 0);
};

override reduce => sub {
    my ($self, @state) = @_;
    my $reader = EDI Class That Knows How To Get Stream

		while ($message = $reader->nextElement) {
			$self->emit($message->FormattedAsAMessage());
			# $self->emit(CopacMessage);
		}
};

package CopacMessage;

override keyValueSet => sub {
    my ($self, $message) = @_;
		return { edisource => fordcopac, data => $message };
};

override reduce => sub {
    my ($self, @state) = @_;
		foreach (@state) {
	    my $source = $EDI->open_source($state->{edisource}, .....)
			$source->do things
			$self->emit( batchmessage => {max => 20, message => <outbound message> } );
		}
};

package BatchMessage;

if scalar @state < 20 oholdoff


