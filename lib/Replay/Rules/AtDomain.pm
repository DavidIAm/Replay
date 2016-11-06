package Replay::Rules::AtDomain;

# This state encapsulates the outstanding requests to create a new project
#
# ATDOMAIN rule
# The list of active domains and the keys in them that we're processing
#
# SendMessageWhen message
# kvs At alltime - { domain => '', keys => [ ] }
#
# SentMessageAt message
# kvs At alltime - { domain => '', keys => [ ] }
#
# Timing message
# kvs At alltime - { timing }
#
# reduce
#   add up domain values.  drop if 0.
#   drop timing message input
#   iterate all nonzero domains
#     if key is less than time
#      emit SentMessageAt { requested, actual, atdomain, time }
#
# send domain specific message for each atdomain/window
# manage the list of atdomains/windows
# increment atdomain/window
# decrement atdomain/window

#$VAR1 = {
#          'Replay' => '20140727',
#          'MessageType' => 'SendMessageWhen',
#          'Message' => {
#                         'min': 1407116462,
#                         'max': 1407116462,
#                         'window': 1407116000,
#                         'atdomain': 'rulename',
#                         'payload': { MessageType: '...', Message: { ... } },
#                       },
#        };
# $VAR2 = {
#          'Replay' => '20140727',
#          'MessageType' => 'SentMessageAt',
#          'Message' => {
#                         'requested': 1407116462',
#                         'actual': 1407116462',
#                         'atdomain': 'rulename',
#                         'sentuuid': 'DFJAKLDJFALDSKF',
#                         'foruuid': 'DFJAKLDJFALDSKF',
#                         'payload': { MessageType: '...', Message: { ... } },
#                       },
#        }
# $VAR2 = {
#          'Replay' => '20140727',
#          'MessageType' => 'Timing',
#          'Message' => {
#                         'epoch' => '1407116462',
#                       },
#        }
# $VAR3 = {
#          'Replay' => '20140727',
#          'MessageType' => 'SendMessageNow',
#          'Message' => {
#                       'epoch' => '1407116462',
#                       'window' => '1407117000',
#                       'atdomain': 'rulename',
#                       },
#        };

use Moose;
use Scalar::Util qw/blessed/;
use List::Util qw/min max/;
use JSON;
use Try::Tiny;
use Replay::Message::Send::Now 0.02;
use Readonly;
with 'Replay::Role::BusinessRule' => { -version => 0.02 };

our $VERSION = q(2);

Readonly my $MAX_EXCEPTION_COUNT => 3;
Readonly my $WINDOW_SIZE         => 1000;
Readonly my $INTERAL_SIZE        => 60;

has '+name' => (default => 'AtDomain');

has '+version' => (default => $VERSION);

# SendMesssageAt for adding to our state
# SentMesssageAt for removing from our state
# Timing for triggering consideration of our state
sub match {
    my ($self, $message) = @_;
    return 1 if $message->{MessageType} eq 'SendMessageWhen';
    return 1 if $message->{MessageType} eq 'SentMessageAt';
    return 1 if $message->{MessageType} eq 'Timing';
    return 0;
}

# only one window for matching with the timing message reliably
sub window {
    my ($self, $message) = @_;
    return 'alltime';
}

# don't care the order
sub compare {
    my ($self, $aa, $bb) = @_;
    return 0;
}

# effectively we're dropping the actual message that is sent in
# because we don't want to store that here, its in the At rule
sub key_value_set {
    my ($self, $message) = @_;

    return q(-) => {
        __TYPE__ => 'request',
        domain   => $message->{Message}{atdomain},
        window   => $message->{Message}{window},
        incr     => 1,
        min      => $message->{Message}{newmin},
        max      => $message->{Message}{newmax},
        }
        if $message->{MessageType} eq 'SendMessageWhen';
    return q(-) => {
        __TYPE__ => 'confirmation',
        domain   => $message->{Message}{atdomain},
        window   => $message->{Message}{window},
        incr     => -1,
        min      => $message->{Message}{newmin},
        max      => $message->{Message}{newmax},
        }
        if $message->{MessageType} eq 'SentMessageAt';
    return q(-) => {
        __TYPE__ => 'sendnow',
        domain   => $message->{Message}{atdomain},
        window   => $message->{Message}{window},
        }
        if $message->{MessageType} eq 'SendMessageNow';
    return q(-) => {
        __TYPE__ => 'trigger',
        sendnow  => 1,
        epoch    => $message->{Message}{epoch}
        }
        if $message->{MessageType} eq 'Timing';
    return;
}

sub reduce {
    my ($self, $emitter, @atoms) = @_;

    # find the latest timing message that has arrived

    # if we get more than one timing message in one reduce, make sure we
    # send for all the appropriate ranges.
    my ($domains) = grep { $_->{__TYPE__} eq 'domains' } @atoms,
        { __TYPE__ => 'domains', D => {} };

    # transmit an event to
    foreach my $atom (sort { $a->{domain} cmp $b->{domain} }
        grep { $_->{__TYPE__} eq 'request' || $_->{__TYPE__} eq 'confirmation' }
        @atoms)
    {

        my $d = $atom->{domain};
        my $w = $atom->{window};
        my $n = $atom->{min};
        my $x = $atom->{max};
        my $i = $atom->{incr};

        $domains->{D}{$d}{$w} ||= { cnt => 0 };

        $domains->{D}{$d}{$w}{min} = $n;
        $domains->{D}{$d}{$w}{max} = $x;

        $domains->{D}{$d}{$w}{cnt} += $i;
    }

    # housekeeping - clean up the domains that are no longer have a count
    foreach my $domain (keys %{ $domains->{D} }) {
        foreach my $window (keys %{ $domains->{D}{$domain} }) {
            if ($domains->{D}{$domain}{$window}{cnt} <= 0) {
                delete $domains->{D}{$domain}{$window};
            }
            if (0 == scalar keys %{ $domains->{D}{$domain} }) {
                delete $domains->{D}{$domain};
            }
        }
    }

    # housekeeping - make a note of events we already requested to send
    foreach my $send_now (grep { $_->{__TYPE__} eq 'sendnow' } @atoms) {
        next
            if !exists $domains->{D}->{ $send_now->{domain} }
            || !
            exists $domains->{D}->{ $send_now->{domain} }->{ $send_now->{window} };
        my $dw = $domains->{D}->{ $send_now->{domain} }->{ $send_now->{window} };
        $dw->{sent} = 1;
    }

    # only if we've gotten a timing message
    my @times = map { $_->{epoch} } grep { $_->{__TYPE__} eq 'trigger' } @atoms;
    if (@times) {

        # send for the particular domains in list and in range
        foreach my $domain (keys %{ $domains->{D} }) {
            foreach my $window (keys %{ $domains->{D}{$domain} }) {
                my $dw = $domains->{D}->{$domain}->{$window};
                foreach
                    my $time ((max grep { $_ && $_ <= $dw->{max} && $_ >= $dw->{min} } @times)
                    || ())
                {
                    $emitter->emit(
                        'map',
                        Replay::Message::Send::Now->new(
                            sendtime => $time,
                            atdomain => $domain,
                            window   => $window,
                        )
                    );
                }
            }
        }
    }

    return if 0 == scalar keys %{ $domains->{D} };
    return $domains;
}

1;

=pod 

=head1 NAME

Replay::Rules::AtDomain - A rule that helps us manage emitting events later

=head1 VERSION

Version 0.01

=head1 SYNOPSIS

Sometimes we want to trigger an event to be sent at a later time, a backoff 
mechanism for retrying is such a candidate

This is only half the state preservation for this logic - there is also a
AtDomain rule which stores the list of domain/windows that need to be activated
to scale more effectively.  

=head1 DESCRIPTION

Each request increments the window-domain count and updates a min/max value.

Each confirmation decrements the window-domain count and updates a min/max value.

Each timing message triggers a SendMessageNow event for each window-domain for
which min is less than and max is more than the time value supplied

=head1 SUBROUTINES/METHODS

=head2 bool = match(message)

returns true if message type is 'SendMessageWhen' or 'SentMessageAt' or
'Timing'

=head2 list (key, value, key, ...) = key_value_set(message)

in case of SendMessageWhen , type is request

key = -
value = request ( window domain sendat incr )

in case of SentMessageAt

key = -
value = confirmation ( atdomain window newmin newmax incr )

in case of SendMessageNow

key = -
value = sendnow ( atdomain window )

in case of Timing

key = -
value = timing ( sendnow epoch )

=head2 window = window(message)

set the appropriate window using epoch_to_window on the 'sendat' field
for SendMessageAt and the specified window for SendMessageNow

=head2 -1|0|1 = compare(message)

sorts events by their send time

=head2 newstatelist = reduce(emitter, statelist)

maintains requests

for confirmation and requests modifies the min and max settings as
indicated

If it finds a request it increments the count in the state for the
indicated domain and window,

If it finds a confirmation it decrements the count in the state for the
indicated domain and window

transmits messages

it finds all of the trigger messages supplied

within each of the domain-window cubbies, it selects the biggest trigger
time and sends a SendMessageNow to trigger the processing of that cubby
in the At rule.

=head2 windowID = epoch_to_window(epoch)

current implimentation just divides the epoch time by 1000, so every 1000
minutes will have its own state set.  Hopefully this is small enough.
Used by both 'window' and 'key_value_set'.

=head1 AUTHOR

David Ihnen, C<< <davidihnen at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-replay at rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Replay>.  I will be
notified, and then you'll automatically be notified of progress on your
bug as I make changes .

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
