package Replay::EventSystem;

# The configuration this requires is
#
# Replay::EventSystem->new( config => <hashref> , [ timeout => # ] );
#
# The event system has three logical channels of events
# Origin - Original external events that are entering the system
# Control - Internal control messages usually about engine state transitions
# Derived - Events that express application state transitions
#
# This code makes available three methods
#
#  origin
#  control
#  derived
#
# Which can be used to access those channels to either emit or subscribe to
# messages
#
# to execute the application, call the ->run method.
#
# If the timeout option is set, it will stop running after that many seconds.
#
#
# my $app = Replay::EventSystem->new( config => <config hash> );
# $app->control->subscribe( sub { handle_control_message(shift) } );
# $app->origin->subscribe( sub { handle_origin_message(shift) } );
# $app->derived->subscribe( sub { handle_derived_message(shift) } );
# $app->run;
#
# sub handle_control_message {
# 	if ($message->action eq 'STAHP')
# 		$app->stop;
# 	}
# }
#

use Moose;

use EV;
use AnyEvent;
use Readonly;
use Carp qw/confess carp cluck/;
use Time::HiRes;
use Try::Tiny;

use Replay::EventSystem::AWSQueue;

my $quitting = 0;

has control => (
    is      => 'ro',
    isa     => 'Object',
    builder => '_build_control',
    lazy    => 1,
    clearer => 'clear_control',
);
has derived => (
    is      => 'rw',
    isa     => 'Object',
    builder => '_build_derived',
    lazy    => 1,
    clearer => 'clear_derived',
);
has origin => (
    is      => 'rw',
    isa     => 'Object',
    builder => '_build_origin',
    lazy    => 1,
    clearer => 'clear_origin',
);
has config => (is => 'ro', isa => 'HashRef[Item]', required => 1);
has domain => (is => 'ro');    # placeholder

sub BUILD {
    my ($self) = @_;
    my ($generalHandler, $establisher);
    die "NO QueueClass CONFIG!?  Make sure its in the locale files" unless $self->config->{QueueClass};
    $self->{stop} = AnyEvent->condvar(cb => sub {exit});
}

sub initialize {
    my $self = shift;
    # initialize our channels
    $self->control->queue;
    $self->origin->queue;
    $self->derived->queue;
}

sub heartbeat {
    my ($self) = @_;
    $self->{hbtimer}
        = AnyEvent->timer(after => 1, interval => 1, cb => sub { print "<3"; });
}

sub run {
    my ($self) = @_;
    $quitting = 0;

    $self->clock;
    $SIG{QUIT} = sub {
        return if $quitting++;
        $self->stop;
        warn('shutdownBySIGQUIT');
    };
    $SIG{INT} = sub {
        return if $quitting++;
        $self->stop;
        warn('shutdownBySIGINT');
    };

    if ($self->config->{timeout}) {
        $self->{stoptimer} = AnyEvent->timer(
            after => $self->config->{timeout},
            cb    => sub { warn "TRYING TO STOP"; $self->stop }
        );
        warn "Setting timeout to " . $self->config->{timeout};
    }

    $self->{polltimer} = AnyEvent->timer(
        after    => 0,
        interval => 0.1,
        cb       => sub {
            print '?';
            $self->poll();
        }
    );
    EV::loop;
}

sub stop {
    my ($self) = @_;
    warn "STOPPING";
    EV::unloop;
    $self->clear_control;
    $self->clear_derived;
    $self->clear_origin;
}

sub poll {
    my ($self) = @_;
    my $activity = 0;
    $activity += $self->control->poll;
		print "c";
    $activity += $self->origin->poll;
		print "o";
    $activity += $self->derived->poll;
		print "d";
    warn "\nPOLL FOUND $activity MESSAGES" if $activity;
}

sub clock {
    my $self           = shift;
    my $lastSeenMinute = time - time % 60;
    AnyEvent->timer(
        after    => 0.25,
        interval => 0.25,
        cb       => sub {
            my $thisMinute = time - time % 60;
            return if $lastSeenMinute == $thisMinute;
            $lastSeenMinute = $thisMinute;
            my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst)
                = localtime(time);
            $self->eventSystem->origin->emit(
                Replay::Message::Envelope->new(
                    message => Replay::Message::Clock->new(
                        epoch   => time,
                        minute  => $min,
                        hour    => $hour,
                        date    => $mday,
                        month   => $mon,
                        year    => $year + 1900,
                        weekday => $wday,
                        yearday => $yday,
                        isdst   => $isdst
                    ),
                    messageType   => 'Timing',
                    effectiveTime => Time::HiRes::time,
                    program       => __FILE__,
                    function      => 'clock',
                    line          => __LINE__,
                )
            );
        }
    );
}

sub _build_queue {
    my ($self, $purpose) = @_;
    try {
        my $classname = $self->config->{QueueClass};
        eval "require $classname";
        die "error requiring: $@" if $@;
    }
    catch {
        die "Unable to load queue class " . $self->config->{QueueClass} . " --> $_ ";
    };
    return $self->config->{QueueClass}
        ->new(purpose => $purpose, config => $self->config,);
}

sub _build_control {
    my ($self) = @_;
    $self->_build_queue('control');
}

sub _build_derived {
    my ($self) = @_;
    $self->_build_queue('derived');
}

sub _build_origin {
    my ($self) = @_;
    $self->_build_queue('origin');
}

1;

