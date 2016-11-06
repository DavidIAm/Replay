package Replay::Role::ClearingBase;

# This is the general logic that will be used by the traditional clearing
# pattern:
#
# 1. there is an event that is a request
# 2. the response from the request results in either a success or an error
# 3. errors result in retry based on an interval calculation
# 4. if the intervals expire there is an exception message and the state ends
# 5. if it resolves there is a success message and the state ends
#
# ClearingBase type rule
# 
#
#$VAR1 = {
#          'Replay' => '20140727',
#          'MessageType' => 'SendMessageAt',
#          'Message' => {
#                         'sendat': 1407116462',
#                         'atdomain': 'rulename',
#                         'payload': { MessageType: 'AAAA', Message: { ... } },
#                         'class': 'Replay::Message::AAAA',
#                       },
#        }
# $VAR2 = {
#          'Replay' => '20140727',
#          'MessageType' => 'SentMessageAt',
#          'Message' => {
#                       'requested' => '1407116462',
#                       'actual'    => '1407116462.27506',
#                       'atdomain': 'rulename',
#                       'foruuid': 'ALSFDJADSKLFJ',
#                       'sentuuid': 'ALSFDJADSKLFJ',
#                       },
#        };

use Moose::Role;
use Replay::BusinessRule 0.02;
use Scalar::Util qw/blessed/;
use List::Util qw/min max/;
use JSON;
use Try::Tiny;
use Time::HiRes qw/gettimeofday/;
use Replay::Message::Sent::At 0.02;
use Replay::Message::Send::When 0.02;
use Replay::Message 0.02;
use Readonly;
extends 'Replay::BusinessRule';
requires qw/initial_match on_error on_exception on_success/;

our $VERSION = q(2);

Readonly my $MAX_EXCEPTION_COUNT => 3;
Readonly my $WINDOW_SIZE         => 1000;
Readonly my $INTERVAL_SIZE       => 60;

# How many retries you may specify
sub retries {
}

sub match {
    my ($self, $message) = @_;
    return 1 if $message->{MessageType} eq 'SendMessageAt';
    return 1 if $message->{MessageType} eq 'SendMessageNow';
    return 0;
}

sub epoch_to_window {
    my $self  = shift;
    my $epoch = shift;
    return $epoch - $epoch % $WINDOW_SIZE + $WINDOW_SIZE;
}

sub window {
    my ($self, $message) = @_;

    # we send this along to rejoin the proper window
    return $message->{Message}{window}
        if $message->{MessageType} eq 'SendMessageNow';
    return $self->epoch_to_window($message->{Message}{sendat})
        if $message->{MessageType} eq 'SendMessageAt';
    return 'unknown';
}

sub compare {
    my ($self, $aa, $bb) = @_;
    return $aa->{sendat} cmp $bb->{sendat};
}

sub key_value_set {
    my ($self, $message) = @_;

    return $message->{Message}{atdomain} || 'generic' => {
        requested => 0,
        window    => $self->window($message),
        uuid      => $message->{UUID},
        %{ $message->{Message} },
        }
        if $message->{MessageType} eq 'SendMessageAt';
    return $message->{Message}->{atdomain},
        {
        atdomain => $message->{Message}->{atdomain},
        epoch    => $message->{Message}->{sendtime}
        }
        if $message->{MessageType} eq 'SendMessageNow';
    return;
}

sub reduce {
    my ($self, $emitter, @atoms) = @_;

    # find the latest SendMessageNow that has arrived
    my $maxtime = max map { $_->{epoch} } grep { defined $_->{epoch} } @atoms,
        { epoch => 0 };

    # transmit any that are ready to send
    # (skipping any timing atoms)
    my @atoms_to_send
        = grep { defined $_->{sendat} && $_->{sendat} <= $maxtime } @atoms;
    my @atoms_to_keep
        = grep { $_->{sendat} > $maxtime } grep { $_->{payload} } @atoms;
    my @newtimes = map { $_->{sendat} } grep { $_->{sendat} } @atoms_to_keep;
    my $newmin   = min @newtimes;
    my $newmax   = max @newtimes;
    foreach my $atom (@atoms_to_send) {

        if ($atom->{sendat} <= $maxtime) {
            my $c = $atom->{class};
            $emitter->emit($atom->{channel}, my $sent = $c->new($atom->{payload}));
            $emitter->emit(
                'map',
                Replay::Message::Sent::At->new(
                    requested => $atom->{sendat},
                    actual    => scalar(gettimeofday),
                    atdomain  => $atom->{atdomain},
                    sentuuid  => $sent->marshall->{UUID},
                    foruuid   => $atom->{uuid},
                    window    => $atom->{window},
                    newmin    => $newmin,
                    newmax    => $newmax,
                )
            );
        }
    }

    # we do this after because there's no sense in adding it to the list within
    # the domain if we've already sent it.
    foreach my $atom (grep { defined $_->{requested} && !$_->{requested} }
        @atoms_to_keep)
    {
        $emitter->emit(
            'map',
            Replay::Message::Send::When->new(
                newmin   => $newmin,
                newmax   => $newmax,
                atdomain => $atom->{atdomain},
                window   => $atom->{window},
            )
        );
        $_->{requested} = 1;
    }
    return @atoms_to_keep;
}

1;

=pod

=head1 NAME

Replay::Rules::At - A rule that helps us manage emitting events later

=head1 VERSION

Version 0.01

=head1 SYNOPSIS

Sometimes we want to trigger an event to be sent at a later time, a backoff 
mechanism for retrying is such a candidate

This is only half the state preservation for this logic - there is also a
AtDomain rule which stores the list of domain/windows that need to be activated
to scale more effectively.  

=head1 DESCRIPTION

Each

=head1 SUBROUTINES/METHODS

=head2 bool = match(message)

returns true if message type is 'SendMessageAt' or 'SendMessageNow'

=head2 list (key, value, key, ...) = key_value_set(message)

in case of SendMessageAt 

key = specified domain
value = PENDING_TYPE: ( message, window, domain, and required ) 

in case of SendMessageNow

key = specified domain
value = TRANSMIT_TYPE: ( atdomain epoch )

=head2 window = window(message)

set the appropriate window using epoch_to_window on the 'sendat' field
for SendMessageAt and the specified window for SendMessageNow

=head2 -1|0|1 = compare(message)

sorts events by their send time

=head2 newstatelist = reduce(emitter, statelist)

maintains requests

If it finds a PENDING_TYPE  with requested not set in the state list
transmits an derived message 'SendMessageWhen' with the window, domain,
and actuation time, and sets 'requested'

transmits messages

It selects the TRANSMIT_TYPE in the list with the latest send time

if it has a send time, it looks through the state list to find all of
the entries whose send time is equal to or less than the indicated time,
transmits them, removes from state, and emits a SentMessageAt message
to origin

=head2 windowID = epoch_to_window(epoch)

current implimentation just divides the epoch time by 1000, so every 1000
minutes will have its own state set.  Hopefully this is small enough.
Used by both 'window' and 'key_value_set'.

=head1 AUTHOR

David Ihnen, C<< <davidihnen at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-replay at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Replay>.  I will be notified, and then you'll automatically be notified of progress on your bug as I make changes .

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
