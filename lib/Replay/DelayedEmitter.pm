package Replay::DelayedEmitter;

use Moose;
use Carp qw/confess/;

our $VERSION = '0.02';

has eventSystem =>
    ( is => 'ro', isa => 'Replay::EventSystem', required => 1,  );
has Timeblocks   => ( is => 'rw', isa => 'ArrayRef', required => 1,  );
has Ruleversions => ( is => 'rw', isa => 'ArrayRef', required => 1,  );
has messagesToSend =>
    ( is => 'rw', isa => 'ArrayRef', default => sub { [] } );
has atomsToDefer => ( is => 'rw', isa => 'ArrayRef', default => sub { [] } );

sub defer {
    my $self = shift;
    my $atom = shift;
    push @{ $self->atomsToDefer }, $atom;
    return;
}

has map => (
    is         => 'ro',
    isa        => 'Replay::DelayedEmitter::Channeled',
    lazy_build => 1,
);

sub _build_map {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my $self = shift;
    my $map = Replay::DelayedEmitter::Channeled->new(
        channel => 'map',
        emitter => $self
    );
    return $map;
}

has reduce => (
    is         => 'ro',
    isa        => 'Replay::DelayedEmitter::Channeled',
    lazy_build => 1,
);

sub _build_reduce {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my $self = shift;
    my $reduce = Replay::DelayedEmitter::Channeled->new(
        channel => 'reduce',
        emitter => $self
    );
    return $reduce;
}

has report => (
    is         => 'ro',
    isa        => 'Replay::DelayedEmitter::Channeled',
    lazy_build => 1,
);

sub _build_report {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my $self = shift;
    my $report = Replay::DelayedEmitter::Channeled->new(
        channel => 'report',
        emitter => $self
    );
    return $report;
}

has control => (
    is         => 'ro',
    isa        => 'Replay::DelayedEmitter::Channeled',
    lazy_build => 1,
);

sub _build_control {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my $self = shift;
    my $control = Replay::DelayedEmitter::Channeled->new(
        channel => 'control',
        emitter => $self
    );
    return $control;
}

has origin => (
    is         => 'ro',
    isa        => 'Replay::DelayedEmitter::Channeled',
    lazy_build => 1,
);

sub _build_origin {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my $self = shift;
    my $origin = Replay::DelayedEmitter::Channeled->new(
        channel => 'origin',
        emitter => $self
    );
    return $origin;
}

sub emit {
    my ( $self, $channel, $message ) = @_;

    #warn(" Replay::EventSystem::Null emit $message");
    # handle single argument construct
    if ( blessed $channel && $channel->isa('Replay::Message') ) {
        $message = $channel;
        $channel = 'map';
    }

    if ( !blessed $message) {
        $message = Replay::Message->new($message);
    }

    # THIS MUST DOES A Replay::Role::Envelope
    if ( !$message->does('Replay::Role::Envelope') ) {
        confess 'Can only emit Replay::Role::Envelope consumer';
    }

#    die "Must emit a Replay message" unless $message->isa('Replay::Message');

    # augment message with metadata from storage
    $message->Timeblocks( $self->Timeblocks );
    $message->Ruleversions( $self->Ruleversions );

    push @{ $self->messagesToSend },
        sub { $self->eventSystem->emit( $channel, $message ) };

    return $message->UUID;
}

sub release {
    my $self = shift;
    foreach ( @{ $self->messagesToSend } ) { $_->(); }
    return;
}

1;

__END__

=pod

=head1 NAME

Replay::DelayedEmitter - buffers up emits until given clearance to transmit

=head1 VERSION

Version 0.01

=head1 SYNOPSIS

my ($self, $state, $meta) = @_;

my $emitter = new Replay::DelayedEmitter(
    eventSystem  => $es,
    Timeblocks   => $stateMeta->{Timeblocks},
    Ruleversions => $stateMeta->{Ruleversions},
);

$emitter->emit('origin',  "new data");
$emitter->emit('map', "derivative data");

if (success) {
    $emitter->release();
}

=head1 CONFIGURATION AND ENVIRONMENT

Implied by context

=head1 DESCRIPTION

Because we don't want to have to worry about keeping track of what we
do or don't have to emit during the processing of a state, we use a
delayedEmitter object.  All of the emits to it are held in a buffer
until the release method is called.

=head1 SUBROUTINES/METHODS

=head2 defer(atom)

The reduce didn't process this atom.  Give it back to the inbox for processing
on the next go around immediately

=head2 emit(channel, message)

=head2 map

returns a similar object configured to send to the map channel the message 
passed to its ->emit method

=head2 control

returns a similar object configured to send to the control channel the message 
passed to its ->emit method

=head2 origin

returns a similar object configured to send to the origin channel the message 
passed to its ->emit method

=head2 emit(message)
=head2 emit(channel, message)

Buffer up an emit for the appropriate channel (map is default)

=head2 release

release the buffered messages

=head2 _build_eventSystem

=head2 _build_storageEngine

=head2 _build_reducer

=head2 _build_mapper

=head2 _build_worm

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

1;
