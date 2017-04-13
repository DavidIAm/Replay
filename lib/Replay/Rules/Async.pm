package Replay::Rules::Async;

# This is the general logic that will be used by the traditional clearing
# pattern:
#
# 1. there is an event that is a request
# 2. the response from the request results in either a success or an error
# 3. errors result in retry based on an interval calculation
# 4. if the intervals expire there is an exception message and the state ends
# 5. if it resolves there is a success message and the state ends
#
# Async role for business rules
#
#
# $VAR1 = {
#          'Replay' => '20140727',
#          'MessageType' => 'Async',
#          'Message' => {
#                         'window': 'dawindow',
#                         'key': 'dakey',
#                         'domain': 'dadomain',
#                         'purpose': 'retry',
#                       },
#        }
# $VAR2 = {
#          'Replay' => '20140727',
#          'MessageType' => 'Async',
#          'Message' => {
#                         'window': 'dawindow',
#                         'key': 'dakey',
#                         'domain': 'dadomain',
#                         'purpose': 'new_input',
#                         'payload': {}
#                       },
#        };

use Moose;
use Scalar::Util qw/blessed/;
use List::Util qw/min max/;
use JSON;
use Try::Tiny;
use Time::HiRes qw/gettimeofday/;
use Replay::Message::Clock;
use Replay::Message::Async;
use Readonly;
with qw/Replay::Role::BusinessRule/;

#requires qw/initial_match attempt on_error on_exception on_success value_set/;
has '+name' => ( default => 'Async' );
our $VERSION = q(2);

Readonly my $DEFAULT_RETRY_COUNT    => 3;
Readonly my $DEFAULT_WINDOW_SIZE    => 600;
Readonly my $DEFAULT_RETRY_INTERVAL => 60;
Readonly my $INTERVAL_SIZE          => 60;
Readonly my $PURPOSE_MAP            => { 'retry' => 1, 'new_input' => 2, };
Readonly my $COMPARE_LESSER         => -1;

# given an error, when to retry this next
sub retry_next_at {
    my ( $self, @atoms ) = @_;
    return;
}

sub window_size_seconds {
    return 600;
}

sub compare {
    my ( $self, $aa, $bb ) = @_;
    return $COMPARE_LESSER if $aa->{MessageType} eq 'Async';
    return 1 if $bb->{MessageType} eq 'Async';
    return $PURPOSE_MAP->{ $aa->{Message}{purpose} }
        <=> $PURPOSE_MAP->{ $bb->{Message}{purpose} };
}

sub match {
    my ( $self, $message ) = @_;
    use Data::Dumper;
    carp 'The message type is ' . Dumper $message->{MessageType};
    return 1 if $message->{MessageType} eq 'Async';
    return 1 if $self->initial_match($message);
    return 0;
}

sub effective_to_window {
}

sub window {
    my ( $self, $message ) = @_;

    # we send this along to rejoin the proper window
    return $message->{Message}{window} if $message->{MessageType} eq 'Async';
    return $message->{UUID};
}

sub attempt_is_success {
    my ( $self, $key, $message ) = @_;

    $self->emit( 'origin', Replay::Message::Async->new( key => $key, ) );
    return $self->on_success($message);
}

sub attempt_is_error {
    my ( $self, $message ) = @_;
    return $self->on_error($message);
}

sub attempt_is_exception {
    my ( $self, $message ) = @_;
    return $self->on_exception($message);
}

sub key_value_set {
    my ( $self, $message ) = @_;

    return
        map { $message->{UUID} => { element => 'original', value => $_ } }
        $self->value_set
        if $self->initial_match($message);

    # return $message->{Message}{key} => {
    # requested => 0,
    # window    => $self->window($message),
    # uuid      => $message->{UUID},
    # }
    # if $self->initial_match($message);

    # #if $message->{MessageType} eq 'Async';

    # the only other type we should see is our initial type
    my $counter = 1;
    return
        map { $message->{UUID} . q/-/ . ( $counter++ ) => { payload => $_ } }
        $self->value_set($message);
}

sub reduce {
    my ( $self, $emitter, @atoms ) = @_;

#requires qw/key_for_set initial_match attempt on_error on_exception on_success value_set/;
# atdomain message

    # inital match <M> attempt < M->ER / EX / SU >

    # # requested is zero
    # if ( $_->{MessageType} eq 'ClearingMachine' ) {
    # }
    # elsif (
    # $_->{MessageType} eq 'ClearingMachineAttempt' {}

    # return @atoms_to_keep;
    return;
}

1;

__END__

=pod

=head1 NAME

Replay::Rules::Async - A rule that helps us manage emitting events later

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

current implementation just divides the epoch time by 1000, so every 1000
minutes will have its own state set.  Hopefully this is small enough.
Used by both 'window' and 'key_value_set'.

=head1 AUTHOR

David Ihnen, C<< <davidihnen at gmail.com> >>

=head1 CONFIGURATION AND ENVIRONMENT

Implied by context

=head1 DIAGNOSTICS

nothing to say here

=head1 DEPENDENCIES

Nothing outside the normal Replay world

=head1 INCOMPATIBILITIES

Nothing to report

=head1 BUGS AND LIMITATIONS

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
AND CONTRIBUTORS 'AS IS' AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES.
THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE, OR NON-INFRINGEMENT ARE DISCLAIMED TO THE EXTENT PERMITTED BY
YOUR LOCAL LAW. UNLESS REQUIRED BY LAW, NO COPYRIGHT HOLDER OR
CONTRIBUTOR WILL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, OR
CONSEQUENTIAL DAMAGES ARISING IN ANY WAY OUT OF THE USE OF THE PACKAGE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut

1;
