package Replay::Reducer;

use Moose;
use Scalar::Util;
use Replay::DelayedEmitter;
use Replay::IdKey;
use Replay::Message;
use Replay::Message::Reduced;
use Replay::Message::Exception::Reducer;
use Scalar::Util qw/blessed/;
use Carp qw/carp/;
use Try::Tiny;

our $VERSION = '0.02';

has ruleSource => ( is => 'ro', isa => 'Replay::RuleSource', required => 1, );

has eventSystem =>
    ( is => 'ro', isa => 'Replay::EventSystem', required => 1, );

has storageEngine =>
    ( is => 'ro', isa => 'Replay::StorageEngine', required => 1, );

has config => (
    is       => 'ro',
    isa      => 'HashRef[Item]',
    required => 0,
    default  => sub { {}, },
);

sub ARRAYREF_FLATTEN_ENABLED_DEFAULT { return 1 }
sub NULL_FILTER_ENABLED_DEFAULT      { return 1 }

sub NULL_FILTER_ENABLED {
    my ($self) = @_;
    if ( $self->config || exists $self->config->{null_filter_enabled} ) {
        return $self->config->{null_filter_enabled};
    }
    return NULL_FILTER_ENABLED_DEFAULT;
}

sub ARRAYREF_FLATTEN_ENABLED {
    my ($self) = @_;
    if ( $self->config || exists $self->config->{arrayref_flatten_enabled} ) {
        return $self->config->{arrayref_flatten_enabled};
    }
    return ARRAYREF_FLATTEN_ENABLED_DEFAULT;
}

sub BUILD {
    my $self = shift;
    my $cb = sub { $self->reduce_wrapper(@_) };
    $self->eventSystem->reduce->subscribe($cb);
}

# accessor - how to get the rule for an idkey
sub rule {
    my ( $self, $idkey ) = @_;
    my $rule = $self->ruleSource->by_idkey($idkey);
    return $rule;
}

sub normalize_envelope {
    my ( $self, $first, @input ) = @_;
    if ( !defined $first ) {
        return ();
    }
    my $ref
        = blessed $first ? $first : ref $first ? $first : { $first, @input };
    if ( blessed $ref) {
        return $ref;
    }
    my $message = Replay::Message->new($ref);
    return $message;
}

sub reducable_message {
    my ( $self, $envelope ) = @_;
    my $type = $envelope->MessageType eq 'Reducable';
    return $type;
}

sub identify {
    my ( $self, $message ) = @_;
    my $identify = Replay::IdKey->new(
        {   name    => $message->{Message}->{name},
            version => $message->{Message}->{version},
            window  => $message->{Message}->{window},
            key     => $message->{Message}->{key},
        }
    );
    return $identify;
}

sub reduce_wrapper {
    my ( $self, @input ) = @_;
    my $envelope = $self->normalize_envelope(@input);

    return if !$self->reducable_message($envelope);
    my $identify = $self->identify($envelope);
    my $exe      = $self->execute_reduce($identify);
    return $exe;
}

sub make_delayed_emitter {
    my ( $self, $meta ) = @_;
    my $eventSystem = $self->eventSystem;
    my $emitter = Replay::DelayedEmitter->new( eventSystem => $eventSystem,
        %{$meta} );
    return $emitter;
}

sub make_reduced_message {
    my ( $self, $idkey ) = @_;
    my $message = Replay::Message::Reduced->new( $idkey->marshall );
    return $message;
}

sub execute_reduce {
    my ( $self, $idkey ) = @_;

    my ( $lock, $meta, @state );
    try {
        ( $lock, $meta, @state )
            = $self->storageEngine->fetch_transitional_state($idkey);
        if ( !$lock || !$lock->locked || !$meta ) {
            return;
        }    # there was nothing to do, apparently
        my $emitter = $self->make_delayed_emitter($meta);
        my @flatten = $self->arrayref_flatten(
            $self->null_filter(
                $self->rule($idkey)->reduce( $emitter, @state )
            )
        );
        use Data::Dumper;

        # warn("execute_reduce ".Dumper($idkey)." flat-".Dumper(\@flatten));
        $self->storageEngine->store_new_canonical_state( $lock, $emitter,
            @flatten );
        my $message = $self->make_reduced_message($idkey);
        $self->eventSystem->control->emit($message);
    }
    catch {
        carp "REDUCING EXCEPTION: $_\n";
        if ( !$lock ) {
            carp "failed to get record lock in reducer.";
        }
        elsif ( $lock->locked ) {
            carp "Reverting state because there was a reduce exception\n";
            $self->storageEngine->revert($lock);
        }
        else {
            carp "Locking error apparently?\n" unless $lock->locked;
        }
        my @hash_list = $idkey->hash_list;
        my $exception
            = blessed $_ && $_->can('trace') ? $_->trace->as_string : $_;
        my $message = Replay::Message::Exception::Reducer->new(
            @hash_list,
            exception => (
                $exception

            ),
        );
        $self->eventSystem->control->emit($message);
    };
    return;
}

sub arrayref_flatten {
    my ( $self, @args ) = @_;
    return @args if !$self->ARRAYREF_FLATTEN_ENABLED;
    my @map = map { 'ARRAY' eq ref $_ ? @{$_} : $_ } @args;
    return @map;
}

sub null_filter {
    my ( $self, @args ) = @_;
    return @args if !$self->NULL_FILTER_ENABLED;
    my @null = map { defined $_ ? $_ : () } @args;
    return @null;
}

1;

__END__

=pod

=head1 NAME

Replay::Reducer

=head1 NAME

Replay::Reducer - the reducer component of the system

=head1 VERSION

Version 0.01

=head1 SYNOPSIS

 my $reducer = Replay::Reducer->new(
   ruleSource => $ruleSource,
   eventSystem => $eventSystem,
   storageEngine => $storageEngine,
 );

 $eventSystem->run;

=head1 CONFIGURATION AND ENVIRONMENT

Implied by context

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
                    Replay::Message::StateATypeOfMessage->new(
                    relayed => "data for state A" 
                    ),
            );
        }
        if (ruleState($index, [@atoms], 'NewStateB')) {
            $emitter->emit(
                'map',
                    Replay::Message::StateBTypeOfMessage->new(
                    relayed => "data for state B"
                    ),
            );
        }
        if (ruleState($index, [@atoms], 'shouldNowRequest')) {
            $emitter->emit(
                'origin',
                    Replay::Message::RPCURLResponseForRequest->new(
                        response => $jsonrpcAgent->get('RPCURL')->content->from_json,
                        url      => $key,
                        window   => $idKey->window,
                    effectiveTime => $atom->{effectiveTime} || $atom->{receivedTime}
                    );
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
