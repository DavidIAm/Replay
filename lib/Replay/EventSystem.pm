package Replay::EventSystem;

use Moose;

use EV;
use AnyEvent;
use Readonly;
use English qw/-no_match_vars/;
use Carp qw/confess carp cluck/;
use Data::Dumper;
use Time::HiRes;
use Replay::Message::Timing;
use Try::Tiny;
use Carp qw/croak carp confess/;

our $VERSION = '0.02';

Readonly my $LTYEAR         => 1900;
Readonly my $SECS_IN_MINUTE => 60;

my $quitting = 0;

has control => (
    is        => 'ro',
    isa       => 'Object',
    builder   => '_build_control',
    predicate => 'has_control',
    lazy      => 1,
    clearer   => 'clear_control',
);
has map => (
    is        => 'rw',
    isa       => 'Object',
    builder   => '_build_map',
    predicate => 'has_map',
    lazy      => 1,
    clearer   => 'clear_map',
);
has reduce => (
    is        => 'rw',
    isa       => 'Object',
    builder   => '_build_reduce',
    predicate => 'has_reduce',
    lazy      => 1,
    clearer   => 'clear_reduce',
);
has report => (
    is        => 'rw',
    isa       => 'Object',
    builder   => '_build_report',
    predicate => 'has_report',
    lazy      => 1,
    clearer   => 'clear_report',
);
has origin => (
    is        => 'rw',
    isa       => 'Object',
    builder   => '_build_origin',
    predicate => 'has_origin',
    lazy      => 1,
    clearer   => 'clear_origin',
);
has originsniffer => (
    is        => 'rw',
    isa       => 'Object',
    builder   => '_build_origin_sniffer',
    predicate => 'has_origin_sniffer',
    lazy      => 1,
    clearer   => 'clear_origin_sniffer',
);
has mapsniffer => (
    is        => 'rw',
    isa       => 'Object',
    builder   => '_build_map_sniffer',
    predicate => 'has_map_sniffer',
    lazy      => 1,
    clearer   => 'clear_map_sniffer',
);
has reducesniffer => (
    is        => 'rw',
    isa       => 'Object',
    builder   => '_build_reduce_sniffer',
    predicate => 'has_reduce_sniffer',
    lazy      => 1,
    clearer   => 'clear_reduce_sniffer',
);
has reportsniffer => (
    is        => 'rw',
    isa       => 'Object',
    builder   => '_build_report_sniffer',
    predicate => 'has_report_sniffer',
    lazy      => 1,
    clearer   => 'clear_report_sniffer',
);
has mode => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
    builder  => '_build_mode',
    lazy     => 1,
);
has config => ( is => 'ro', isa => 'HashRef[Item]', required => 1 );
has domain => ( is => 'ro' );    # placeholder

sub BUILD {
    my ($self) = @_;
    if ( not $self->config->{EventSystem}->{Mode} ) {
        confess
            q(NO EventSystem Mode CONFIG!?  Make sure its in the locale files)
            . Dumper $self->config;
    }
    $self->{stop} = AnyEvent->condvar( cb => sub {exit} );
    return;
}

sub initialize {
    my $self = shift;

    # initialize our channels
    $self->control->bound_queue;
    $self->origin->bound_queue;
    $self->map->bound_queue;
    $self->reduce->bound_queue;
    $self->report->bound_queue;
    return;
}

sub heartbeat {
    my ($self) = @_;
    return $self->{hbtimer} = AnyEvent->timer(
        after    => 1,
        interval => 1,
        cb       => sub { print q(<3) or croak q(cannot print heartbeat?) }
    );
}

sub run {
    my ($self) = @_;
    $quitting = 0;

    $self->clock;
    carp q(SIGQUIT will stop loop) if $ENV{DEBUG_REPLAY_TEST};
    local $SIG{QUIT} = sub {
        return if $quitting++;
        $self->stop;
        $self->clear;
        carp('shutdownBySIGQUIT') if $ENV{DEBUG_REPLAY_TEST};
    };
    carp q(SIGINT will stop loop) if $ENV{DEBUG_REPLAY_TEST};
    local $SIG{INT} = sub {
        return if $quitting++;
        $self->stop;
        $self->clear;
        carp('shutdownBySIGINT') if $ENV{DEBUG_REPLAY_TEST};
    };

    if ( $self->config->{timeout} ) {
        $self->{stoptimer} = AnyEvent->timer(
            after => $self->config->{timeout},
            cb    => sub {
                carp q(Timeout triggered.) if $ENV{DEBUG_REPLAY_TEST};
                $self->stop;
            }
        );
        carp q(Setting loop timeout to ) . $self->config->{timeout}
            if $ENV{DEBUG_REPLAY_TEST};
    }

    $self->{polltimer} = AnyEvent->timer(
        after    => 0,
        interval => 0.1,
        cb       => sub {
            $self->poll();
        }
    );
    carp q(Event loop startup now) if $ENV{DEBUG_REPLAY_TEST};
    EV::loop;
    return;
}

sub stop {
    my ($self) = @_;
    carp q(Event loop shutdown by request) if $ENV{DEBUG_REPLAY_TEST};
    EV::unloop;
    return;
}

sub clear {
    my ($self) = @_;
    $self->clear_control;
    $self->clear_map;
    $self->clear_reduce;
    $self->clear_report;
    $self->clear_origin;
    $self->clear_map_sniffer;
    $self->clear_reduce_sniffer;
    $self->clear_report_sniffer;
    $self->clear_origin_sniffer;
    my $class
        = 'Replay::EventSystem::' . $self->config->{EventSystem}->{Mode};
    $class->done;
    return;
}

sub emit {
    my ( $self, $channel, $message ) = @_;

    if ( !blessed $message) {
        $message = Replay::Message->new($message);
    }

    # THIS MUST DOES A Replay::Role::Envelope
    if ( !$message->does('Replay::Role::Envelope') ) {
        confess 'Can only emit Replay::Role::Envelope consumer';
    }

    if ( !$self->can($channel) ) {
        confess "Unknown channel $channel";
    }

    $self->$channel->emit( $message->marshall );
    return $message->UUID;

}

use EV;

sub poll {
    my ( $self, @purposes ) = @_;
    if ( 0 == scalar @purposes ) {
        @purposes = (
            ( $self->has_origin         ? qw(origin)        : () ),
            ( $self->has_control        ? qw(control)       : () ),
            ( $self->has_map            ? qw(map)           : () ),
            ( $self->has_reduce         ? qw(reduce)        : () ),
            ( $self->has_report         ? qw(report)        : () ),
            ( $self->has_map_sniffer    ? qw(mapsniffer)    : () ),
            ( $self->has_reduce_sniffer ? qw(reducesniffer) : () ),
            ( $self->has_report_sniffer ? qw(reportsniffer) : () ),
            ( $self->has_origin_sniffer ? qw(originsniffer) : () ),
        );
    }
    my $activity = 0;
    foreach my $purpose (@purposes) {

        #try {
        $activity += $self->$purpose->poll();

        #}
        #catch {
        #    confess "Unable to do poll for purpose $purpose: $_";
        #    EV::unloop;
        #};
    }
    return;
}

sub clock {
    my $self             = shift;
    my $last_seen_minute = time - time % $SECS_IN_MINUTE;
    carp q(Clock tick started) if $ENV{DEBUG_REPLAY_TEST};
    $self->{clock} = AnyEvent->timer(
        after    => 0.25,
        interval => 0.25,
        cb       => sub {
            my $this_minute = time - time % $SECS_IN_MINUTE;
            return if $last_seen_minute == $this_minute;
            carp "Clock tick on minute $this_minute"
                if $ENV{DEBUG_REPLAY_TEST};
            $last_seen_minute = $this_minute;
            my ($sec,  $min,  $hour, $mday, $mon,
                $year, $wday, $yday, $isdst
            ) = localtime time;
            my $time =  Replay::Message::Timing->new(
                    epoch    => time,
                    minute   => $min,
                    hour     => $hour,
                    date     => $mday,
                    month    => $mon,
                    year     => $year + $LTYEAR,
                    weekday  => $wday,
                    yearday  => $yday,
                    isdst    => $isdst,
                    program  => __FILE__,
                    function => 'clock',
                    line     => __LINE__,
                );
            $self->emit(
                'origin',
                $time
            );
        }
    );
    return;
}

sub _build_mode {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my $self = shift;
    if ( not $self->config->{EventSystem}->{Mode} ) {
        croak q(No EventSystem Mode?);
    }
    my $class
        = 'Replay::EventSystem::' . $self->config->{EventSystem}->{Mode};
    try {
        my $path = $class . '.pm';
        $path =~ s{::}{/}gxsm;
        eval { require $path }
            or croak qq(error requiring class $class : ) . $EVAL_ERROR;
    }
    catch {
        confess q(No such event system mode available )
            . $self->config->{EventSystem}
            . " --> $_";
    };
    return $class;
}

sub _build_queue {
    my ( $self, $purpose, $mode ) = @_;
    my $classname = $self->mode;
    try {
        try {
            my $path = $classname . '.pm';
            $path =~ s{::}{/}xgsm;
            if ( !eval { require $path } ) {
                croak $EVAL_ERROR;
            }
        }
        catch {
            croak "error requiring: $_";
        };
    }
    catch {
        croak q(Unable to load queue class )
            . $self->config->{EventSystem}->{Mode}
            . " --> $_ ";
    };
    my $queue = $classname->new(
        purpose => $purpose,
        config  => $self->config,
        mode    => $mode
    );
    return $queue;
}

sub _build_control {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my ($self) = @_;
    my $control =  $self->_build_queue( 'control', 'fanout' );
    return $control;
}

sub _build_reduce_sniffer {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my ($self) = @_;
    my $reduce = $self->_build_queue( 'reduce', 'fanout' );
    return $reduce;
}

sub _build_report_sniffer {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my ($self) = @_;
    my $report = $self->_build_queue( 'report', 'fanout' );
    return $report;
}

sub _build_map_sniffer {       ## no critic (ProhibitUnusedPrivateSubroutines)
    my ($self) = @_;
    my $map =  $self->_build_queue( 'map', 'fanout' );
    return $map;
}

sub _build_map {               ## no critic (ProhibitUnusedPrivateSubroutines)
    my ($self) = @_;
    my $map =  $self->_build_queue( 'map', 'topic' );
    return $map;
}

sub _build_reduce {            ## no critic (ProhibitUnusedPrivateSubroutines)
    my ($self) = @_;
    my $reduce = $self->_build_queue( 'reduce', 'topic' );
    return $reduce;
}

sub _build_report {            ## no critic (ProhibitUnusedPrivateSubroutines)
    my ($self) = @_;
    my $report = $self->_build_queue( 'report', 'topic' );
    return $report;
}

sub _build_origin {            ## no critic (ProhibitUnusedPrivateSubroutines)
    my ($self) = @_;
    my $origin = $self->_build_queue( 'origin', 'topic' );
    return $origin;
}

sub _build_origin_sniffer {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my ($self) = @_;
    my $origin = $self->_build_queue( 'origin', 'fanout' );
    return $origin;
}

1;

__END__

=pod

=head1 NAME

Replay::EventSystem - general communication channel interface

=head1 VERSION

Version 0.01

=head1 SYNOPSIS

 Replay::EventSystem->new( config => { QueueClass => '...' }, [ timeout => # ] );

=head1 CONFIGURATION AND ENVIRONMENT

This simply is.  Its the submodule implementations that are configured

=head1 DESCRIPTION
This is the Event System interface module.  It interfaces with a set of 
communication channels, taking a config hash with the QueueClass to 
instantiate and any other queue class specific configuration needed

 Replay::EventSystem->new( config => { QueueClass => '...' }, [ timeout => # ] );

The event system has three logical channels of events

 Origin - Original external events that are entering the system
 Control - Internal control messages usually about engine state transitions
 map - Events that express application state transitions

=head1 Communication Channel API

Any communication channel must implement these methods.  They must be distinct
objects per purpose.

=head2 $channel = [QueueClass]->new( purpose => 'label', ... )

return a new communication channel object distinct for the specified purpose

=head2 $channel->subscribe( sub { my $message = shift; ... } )

register a callback that will be triggered with each message found during 
a poll

=head2 $success = $channel->emit( $message );

emit a message on this channel.  it is expected to be received by all of
the subscribers to the channel within the system including this one. The 
possible locations of those subscribers is limited only by the module used 
and programs running.

=head2 $messages_handled = $channel->poll( );

Poll for new messages and call the subscribed hooks for each.

=head1 SUBROUTINES/METHODS

=head2 run

Start the main event loop for the event system.

Starts the clock - a once-every-minute message indicating the current time.

Sets up a SIGINT handler to cleanly bring down the queues

Sets up a SIGQUIT handler to cleanly bring down the queues

If the timeout option was indicated at construction, sets up a timer to
stop the loop after that many seconds

Calls the poll() function as often as possible

=head2 initialize

call to bring up the connections for all topics and queues

otherwise, they're only initialized when referenced.  This is important
for situations where the eventsystem is only being used to transmit a
quick message, rather than supporting an entire framework

=head2 BUILD

Sets up the stopping conditional variable, and checks to make sure the
QueueClass is configured

=head2 clock

Sets up a timer that emits a message each minute for use by cron-type rules

=head2 stop

Calling this subroutine triggers the stopping of the event loop.

You can use it to do things like stop the system on a particular message!

=head2 heartbeat

Call to start printing a heartbeat every second.

=head2 control

call to access the control purpose channel

=head2 clear

call to clear all of the subscriptions from memory

=head2 origin

call to access the origin purpose channel

=head2 map

call to access the map purpose channel

=head2 emit( purpose, message )

Send the specified message on the specified channel

=head2 poll( [purpose, ...] )

Check for messages on specified - or ALL three channels if none specified

=head2 subscribe( purpose, subroutineref )

Add this subroutine to the subscribed hooks for the specified channel

=cut

=head1 AUTHOR

David Ihnen, C<< <davidihnen at gmail.com> >>

=head1 DIAGNOSTICS

nothing to say here

=head1 DEPENDENCIES

Nothing outside the normal Replay world

=head1 INCOMPATIBILITIES

Nothing to report

=head1 BUGS AND LIMITATIONS

Please report any bugs or feature requests to C<bug-replay at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Replay>.  I will be notified, and then you'

        ll automatically be notified of progress on your bug as I make changes .

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Replay


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Replay>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Replay>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Replay>

=item * Search CPAN

L<http://search.cpan.org/dist/Replay/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2014 David Ihnen.

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). You may obtain a
copy of the full license at:

L<http://www.perlfoundation.org/artistic_license_2_0>

Any use, modification, and distribution of the Standard or Modified
Versions is governed by this Artistic License. By using, modifying or
distributing the Package, you accept this license. Do not use, modify,
or distribute the Package, if you do not accept this license.

If your Modified Version has been derived Modified Version made
by someone other than you, you are nevertheless required to ensure that
your Modified Version complies with the requirements of this license.

This license does not grant you the right to use any trademark, service
mark, tradename, or logo of the Copyright Holder.

This license includes the non-exclusive, worldwide, free-of-charge
patent license to make, have made, use, offer to sell, sell, import and
otherwise transfer the Package with respect to any patent claims
licensable by the Copyright Holder that are necessarily infringed by the
Package. If you institute patent litigation (including a cross-claim or
counterclaim) against any party alleging that the Package constitutes
direct or contributory patent infringement, then this Artistic License
to you shall terminate on the date that such litigation is filed.

Disclaimer of Warranty: THE PACKAGE IS PROVIDED BY THE COPYRIGHT HOLDER
AND CONTRIBUTORS "AS IS' AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES.
THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE, OR NON-INFRINGEMENT ARE DISCLAIMED TO THE EXTENT PERMITTED BY
YOUR LOCAL LAW. UNLESS REQUIRED BY LAW, NO COPYRIGHT HOLDER OR
CONTRIBUTOR WILL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, OR
CONSEQUENTIAL DAMAGES ARISING IN ANY WAY OUT OF THE USE OF THE PACKAGE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut

1;

