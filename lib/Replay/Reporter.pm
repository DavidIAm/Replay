package Replay::Reporter;

use Moose;
use Scalar::Util;
use Replay::DelayedEmitter;
use Replay::Message::ReporterException;
use Replay::Message::Reported;
use Replay::IdKey;
use Replay::Message;
use Scalar::Util qw/blessed/;
use Carp qw/carp/;
use Try::Tiny;

our $VERSION = '0.03';

has ruleSource => (is => 'ro', isa => 'Replay::RuleSource', required => 1);

has eventSystem => (is => 'ro', isa => 'Replay::EventSystem', required => 1);

has reportEngine =>
    (is => 'ro', isa => 'Replay::ReportEngine', required => 1,);

sub BUILD {
    my $self = shift;
    $self->eventSystem->report->subscribe(
        sub {
            $self->report_wrapper(@_);
        }
    );
    return;
}

# accessor - how to get the rule for an idkey
sub rule {
    my ($self, $idkey) = @_;
    return $self->ruleSource->by_idkey($idkey);
}

sub extract_idkey {
    my ($self, $envelope) = @_;
    my ($message, $idkey);
    if (blessed $envelope) {
        $message = $envelope->Message;
        $idkey   = Replay::IdKey->new(
            {   name    => $message->name,
                version => $message->version,
                window  => $message->window,
                key     => $message->key,
            }
        );
    }
    elsif (blessed $envelope->{Message}) {
        $message = $envelope->{Message};
        $idkey   = Replay::IdKey->new(
            {   name    => $message->name,
                version => $message->version,
                window  => $message->window,
                key     => $message->key,
            }
        );
    }
    else {

        $message = $envelope->{Message};
        $idkey   = Replay::IdKey->new($message);

    }
    return $idkey, $message if wantarray;
    return $idkey;
}

sub report_wrapper {
    my ($self, $first, @input) = @_;
    my $envelope
        = blessed $first ? $first : ref $first ? $first : { $first, @input };
    my $type
        = blessed $envelope ? $envelope->MessageType : $envelope->{MessageType};

    my ($uuid, $meta, @state, $idkey);
    try {
        return
               unless $type eq 'NewCanonical'
            or $type eq 'ReportNewDelivery'
            or $type eq 'ReportNewSummary';
        $idkey = $self->extract_idkey($envelope);

        $meta = $self->reportEngine->update_delivery($idkey)
            if $type eq 'NewCanonical';
        $meta = $self->reportEngine->update_summary($idkey)
            if $type eq 'ReportNewDelivery';
        $meta = $self->reportEngine->update_globsummary($idkey)
            if $type eq 'ReportNewSummary';

        $self->eventSystem->control->emit(
            Replay::Message::Reported->new(
                $idkey->hash_list,
                inReactionToType => $type,
                inReactionToUUID => (blessed $envelope ? $envelope->UUID : $envelope->{UUID}),
            ),
        );
    }
    catch {
        carp "REPORTING EXCEPTION: $_";
        $self->eventSystem->control->emit(
            Replay::Message::ReporterException->new(
                ($idkey ? $idkey->hash_list : ()),
                exception => (blessed $_ && $_->can('trace') ? $_->trace->as_string : $_),
            )
        );
    };
    return;
}

1;

__END__

=pod

=head1 NAME

Replay::Reporter

=head1 NAME

Replay::Reporter - the reducer component of the system

=head1 VERSION

Version 0.01

=head1 SYNOPSIS

my $reducer = Replay::Reporter->new(
   ruleSource => $ruleSource,
   eventSystem => $eventSystem,
   reportEngine => $reportEngine,
 );
$eventSystem->run;

=cut

=head1 DESCRIPTION

The reducer listens for Replay::Message::Reducable messages on the
report channel (which it subscribes to on create)

When it sees one, it attempts to retrieve the rule from its rule source.

If it finds the rule, it attempts to retrieve the transitional state
from the engine

If it gets the transitional state, it processes the state with the reduce
method of the rule to a (possibly) new set of atoms - while collecting
a series of events to possibly emit later.

It then attempts to store the new canonical state into the engine

Upon success, it transmits all of the events it buffered up during the reduce


You must follow these Rules:

You will get an emitter and a list of atoms to reduce, sorted by method
compare

You can shorten this list or leave it the same, you will return this list.

Any state changes should cause the emit to be caused.


EXTERNAL INFORMATION - CRITICAL TO CORRECT OPERATION OF SYSTEM

All external information pulled into the system needs to come through the
origin channel.  I know its counterintuitive to have the information and
emit it rather than use it, but if its not done this way, the integrity
of the system's data flows is destroyed.  There be dragons there.  Don't
do it. You won't like the results. If you don't understand why... learn more
about the system first.

# an input message might look like this
{ MessageType => 'TypeThatGetsRequest', Message => { url => 'URI' } }

# we will match both the type that gets, and the response type
# so they will be in the same state
override match => sub {
    my ($self, $message) = @_;
    return
        unless $message->MessageType eq 'TypeThatGetsRequest'
        || $message->MessageType eq 'RPCURLResponseForRequest';
    my @keyvalueset;

    # both message types store the key to use in the 'url' parameter
    push @keyvaluset, $message->{Message}->{url}, $message
        if $message->{Message}->{url};
    return @keyvalueset;
};

# we get the window from the response message to make sure its in the same
# state later.
override window => sub {
    my ($self, $message) = @_;
    return $message->{Message}->{window}
        if ($message->{MessageType} eq 'RPCURLResponseForRequest');
    return myWindowChooserAlgorithm($message);
};

# We sort by the url, then by the message type, which  makes sure all the
# responses are right beside all the requests
override compare => sub {
    my ($self, $atom) = @_;

    # sort by url, with backup on MessageType putting responses immediately
    # before requests
    return $atom->{MessageType} cmp $atom->{MessageType}
        unless $atom->{url} cmp $atom->{url};
};

# in the reduce, we use our ruleState helper (unimportant detail in
# this example) to determine if we should emit one of two derived messages
# (based only on information within the system, or origin (based on
# information gotten from outside the system) events describing the state
# change information
override reduce => sub {
    my ($idkey, $emitter, @atoms);
    my @outatoms;
    foreach my $index (0 .. $#atoms) {
        if (ruleState($index, [@atoms], 'NewStateA')) {
            $emitter->emit(
                'map',
                    MessageType => 'StateATypeOfMessage',
                    relayed => "data for state A" 
            );
        }
        if (ruleState($index, [@atoms], 'NewStateB')) {
            $emitter->emit(
                'map',
                    MessageType => 'StateBTypeOfMessage',
                    relayed => "data for state B"
            );
        }
        if (ruleState($index, [@atoms], 'shouldNowRequest')) {
            $emitter->emit(
                'origin',
                    MessageType => 'RPCURLResponseForRequest',
                        response => $jsonrpcAgent->get('RPCURL')->content->from_json,
                        url      => $key,
                        window   => $idKey->window,
                    effectiveTime => $atom->{effectiveTime} || $atom->{receivedTime}
                );
            );
            $atom->{requested} => JSON::true;
        }
        if (ruleState($index, [@atoms], 'keepThisAtom')) {
            push @outatoms, $atoms[$index];
        }
    }
    return @outatoms;
};

sub ruleState                {...}
sub myWindowChooserAlgorithm {...}

=head1 DESCRIPTION 

the reporter subscribes to the report channel

When the reporter sees a NewCanonical message, it calls the report 
engine implimentation with 'update_delivery' method

When the reporter sees a ReportNewDelivery message, it calls the report 
engine implimentation with 'update_summary' method

When the reporter sees a ReportNewSummary message, it calls the report 
engine implimentation with 'update_globsummary' method

When the reporter sees a Freeze message, it calls the report 
engine implimentation with 'freeze' method

When the reporter sees a Freeze message, it calls the report 
engine implimentation with 'freeze' method

=head1 SUBROUTINES/METHODS

=head2 BUILD

The moose setup/initializer function - mostly it just subscribes to the
event channel so it will know when to act.

=head2 rule

accessor for finding a rule by key

=head2 reduce_wrapper

this wraps around the individual business rule's reduce function, taking
care of the business logic of retrieving the state, calling the reduce
function, storing the result, and conditionally emitting the buffered events.

=cut

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

1;    # End of Replay

1;
