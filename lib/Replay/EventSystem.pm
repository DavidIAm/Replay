package Replay::EventSystem;

use Moose;

use EV;
use AnyEvent;
use Readonly;
use English qw/-no_match_vars/;
use Carp qw/confess carp cluck/;
use Time::HiRes;
use Replay::Message::Timing;
use Try::Tiny;
use Carp qw/croak carp/;

use Replay::EventSystem::AWSQueue;

our $VERSION = '0.02';

Readonly my $LTYEAR         => 1900;
Readonly my $SECS_IN_MINUTE => 60;

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
has originsniffer => (
    is      => 'rw',
    isa     => 'Object',
    builder => '_build_origin_sniffer',
    lazy    => 1,
    clearer => 'clear_origin_sniffer',
);
has derivedsniffer => (
    is      => 'rw',
    isa     => 'Object',
    builder => '_build_derived_sniffer',
    lazy    => 1,
    clearer => 'clear_derived_sniffer',
);
has config => (is => 'ro', isa => 'HashRef[Item]', required => 1);
has domain => (is => 'ro');    # placeholder

sub BUILD {
    my ($self) = @_;
    if (not $self->config->{QueueClass}) {
        croak q(NO QueueClass CONFIG!?  Make sure its in the locale files);
    }
    $self->{stop} = AnyEvent->condvar(cb => sub {exit});
    return;
}

sub initialize {
    my $self = shift;

    # initialize our channels
    $self->control->bound_queue;
    $self->origin->bound_queue;
    $self->derived->bound_queue;
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
    carp q(SIGQUIT will stop loop);
    local $SIG{QUIT} = sub {
        return if $quitting++;
        $self->stop;
        $self->clear;
        carp('shutdownBySIGQUIT');
    };
    carp q(SIGINT will stop loop);
    local $SIG{INT} = sub {
        return if $quitting++;
        $self->stop;
        $self->clear;
        carp('shutdownBySIGINT');
    };

    if ($self->config->{timeout}) {
        $self->{stoptimer} = AnyEvent->timer(
            after => $self->config->{timeout},
            cb    => sub { carp q(Timeout triggered.); $self->stop }
        );
        carp q(Setting loop timeout to ) . $self->config->{timeout};
    }

    $self->{polltimer} = AnyEvent->timer(
        after    => 0,
        interval => 0.1,
        cb       => sub {
            $self->poll();
        }
    );
    carp q(Event loop startup now);
    EV::loop;
    return;
}

sub stop {
    my ($self) = @_;
    carp q(Event loop shutdown by request);
    EV::unloop;
    return;
}

sub clear {
    my ($self) = @_;
    $self->clear_control;
    $self->clear_derived;
    $self->clear_origin;
    $self->clear_derived_sniffer;
    $self->clear_origin_sniffer;
    $self->config->{QueueClass}->done;
    return;
}

sub emit {
    my ($self, $channel, $message, @rest) = @_;
    return $self->$channel->emit(Replay::Message->new(ref $message ? $message : $message => @rest )->marshall)
        if $self->can($channel);
    use Carp qw/confess/;
    confess "Unknown channel $channel";

}

use EV;

sub poll {
    my ($self, @purposes) = @_;
    if (0 == scalar @purposes) {
        @purposes = qw/origin derived control derivedsniffer originsniffer/;
    }
    my $activity = 0;
    foreach my $purpose (@purposes) {
        try {
            $activity += $self->$purpose->poll();
        }
        catch {
            confess "Unable to do poll for purpose $purpose: $_";
            EV::unloop;
        };
    }
    return;
}

sub clock {
    my $self             = shift;
    my $last_seen_minute = time - time % $SECS_IN_MINUTE;
    carp q(Clock tick started);
    $self->{clock} = AnyEvent->timer(
        after    => 0.25,
        interval => 0.25,
        cb       => sub {
            my $this_minute = time - time % $SECS_IN_MINUTE;
            return if $last_seen_minute == $this_minute;
            carp "Clock tick on minute $this_minute";
            $last_seen_minute = $this_minute;
            my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst)
                = localtime time;
            $self->emit(
                'origin',
                Replay::Message::Timing->new(
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
                )
            );
        }
    );
    return;
}

sub _build_queue {
    my ($self, $purpose, $mode) = @_;
    try {
        my $classname = $self->config->{QueueClass};
        try {
            if (eval "require $classname") {
            }
            else {
                croak $EVAL_ERROR;
            }
        }
        catch {
            croak "error requiring: $_";
        };
    }
    catch {
        croak q(Unable to load queue class )
            . $self->config->{QueueClass}
            . " --> $_ ";
    };
    my $queue = $self->config->{QueueClass}
        ->new(purpose => $purpose, config => $self->config, mode => $mode);
    return $queue;
}

sub _build_control {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my ($self) = @_;
    return $self->_build_queue('control', 'fanout');
}

sub _build_derived_sniffer {   ## no critic (ProhibitUnusedPrivateSubroutines)
    my ($self) = @_;
    return $self->_build_queue('derived', 'fanout');
}

sub _build_derived {           ## no critic (ProhibitUnusedPrivateSubroutines)
    my ($self) = @_;
    return $self->_build_queue('derived', 'topic');
}

sub _build_origin {            ## no critic (ProhibitUnusedPrivateSubroutines)
    my ($self) = @_;
    return $self->_build_queue('origin', 'topic');
}

sub _build_origin_sniffer {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my ($self) = @_;
    return $self->_build_queue('origin', 'fanout');
}

1;

__END__

=pod

=head1 NAME

Replay::EventSystem - general communication channel interface

=head1 VERSION

Version 0.01

=head1 SYNOPSIS

This is the Event System interface module.  It interfaces with a set of 
communication channels, taking a config hash with the QueueClass to 
instantiate and any other queue class specific configuration needed

 Replay::EventSystem->new( config => { QueueClass => '...' }, [ timeout => # ] );

The event system has three logical channels of events

 Origin - Original external events that are entering the system
 Control - Internal control messages usually about engine state transitions
 Derived - Events that express application state transitions

=head1 Communication Channel API

Any communication channel must impliment these methods.  They must be distinct
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

=head2 derived

call to access the derived purpose channel

=head2 emit( purpose, message )

Send the specified message on the specified channel

=head2 poll( [purpose, ...] )

Check for messages on specified - or ALL three channels if none specified

=head2 subscribe( purpose, subroutineref )

Add this subroutine to the subscribed hooks for the specified channel

=cut

=head1 AUTHOR

David Ihnen, C<< <davidihnen at gmail.com> >>

=head1 BUGS

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

If your Modified Version has been derived from a Modified Version made
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

