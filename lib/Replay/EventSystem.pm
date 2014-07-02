package Replay::EventSystem;

# The configuration this requires is
#
# Replay::EventSystem->new( locale => <Config::Locale> , [ timeout => # ] );
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
# my $app = Replay::EventSystem->new( locale => <Config::Locale> );
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

use Replay::EventSystem::AWSQueue;
sub queue_class {'Replay::EventSystem::AWSQueue'}

has timeout => (is => 'ro', isa => 'Int', predicate => 'has_timeout');
has control => (
    is      => 'ro',
    isa     => queue_class(),
    builder => '_build_control',
    lazy    => 1,
    clearer => 'clear_control',
);
has derived => (
    is      => 'rw',
    isa     => queue_class(),
    builder => '_build_derived',
    lazy    => 1,
    clearer => 'clear_derived',
);
has origin => (
    is      => 'rw',
    isa     => queue_class(),
    builder => '_build_origin',
    lazy    => 1,
    clearer => 'clear_origin',
);
has locale => (is => 'ro', isa => 'Config::Locale', required => 1);
has domain => (is => 'ro');  # placeholder

sub BUILD {
    my ($self) = @_;
    my ($generalHandler, $establisher);
    die "NO REPLAY CONFIG??" unless $self->locale->config->{Replay};
    $self->{stop} = AnyEvent->condvar(cb => sub {exit});
}

sub run {
    my ($self) = @_;
    $self->{hbtimer}
        = AnyEvent->timer(after => 1, interval => 1, cb => sub { print "<3"; });
    $self->{stoptimer} = AnyEvent->timer(
        after => $self->timeout,
        cb    => sub { warn "TRYING TO STOP"; $self->stop }
    ) if $self->has_timeout;
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
    $self->clear_control;
    $self->clear_derived;
    $self->clear_origin;
    EV::unloop;
}

sub poll {
    my ($self) = @_;
    my $activity = 0;
    $activity += $self->control->poll;
    $activity += $self->origin->poll;
    $activity += $self->derived->poll;
    warn "HANDLED $activity" if $activity;
}

sub _build_queue {
    my ($self, $purpose) = @_;
    return queue_class->new(purpose => $purpose, locale => $self->locale,);
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

