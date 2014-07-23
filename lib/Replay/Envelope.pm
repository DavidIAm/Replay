package Replay::Envelope;

use Moose::Role;
use Time::HiRes qw/gettimeofday/;
use Data::UUID;

has Message => (
    is          => 'ro',
    isa         => 'Str',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'envelope' },
);
has Program => (
    is          => 'ro',
    isa         => 'Str',
    predicate   => 'has_program',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'envelope' },
);
has Function => (
    is          => 'ro',
    isa         => 'Str',
    predicate   => 'has_function',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'envelope' },
);
has Line => (
    is          => 'ro',
    isa         => 'Str',
    predicate   => 'has_line',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'envelope' },
);
has EffectiveTime => (
    is          => 'ro',
    isa         => 'Str',
    predicate   => 'has_effective_time',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'envelope' },
);
has CreatedTime => (
    is          => 'ro',
    isa         => 'Str',
    predicate   => 'has_created_time',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'envelope' },
    builder     => '_now'
);
has ReceivedTime => (
    is          => 'ro',
    isa         => 'Str',
    predicate   => 'has_recieved_time',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'envelope' },
    builder     => '_now'
);

has UUID => (
    is          => 'ro',
    isa         => 'Str',
    builder     => '_build_uuid',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'envelope' },
);

sub marshall {
    my $self     = shift;
    my $envelope = {Messsage    => $self,
        MessageType => $self->MessageType,
        UUID        => $self->UUID,
        ($self->has_program        ? (Program        => $self->Program)       : ()),
        ($self->has_function       ? (Function       => $self->Function)      : ()),
        ($self->has_line           ? (Line           => $self->Line)          : ()),
        ($self->has_effective_time ? (Effective_time => $self->EffectiveTime) : ()),
        ($self->has_created_time   ? (Created_time   => $self->CreatedTime)   : ()),
        ($self->has_received_time  ? (Received_time  => $self->ReceivedTime)  : ()),
    };
    return $envelope; 
    
}

sub _now {
    my $self = shift;
    return +gettimeofday;
}

sub _build_uuid {
    my $self = shift;
    my $ug   = Data::UUID->new;
    return $ug->to_string($ug->create());
}

has Timeblocks => ( is => 'ro', isa => 'ArrayRef', );
has Ruleversions => ( is => 'ro', isa => 'ArrayRef[HashRef]', );
has Windows => ( is => 'ro', isa => 'ArrayRef[Str]', );

=head1 NAME

Replay::Message::Envelope - General replay message envelope 

=head1 VERSION

Version 0.01

=cut

=head1 SYNOPSIS

This is a message data type envelop used for most messages on the derived channel

effectiveTime - the time this event refers to
receivedTime - the time the message entered the system
createdTime - the time the message was created originally
timeblocks - an array of the time block identifiers related to this message state
ruleversions - an array of { name:, version: } objects related to this message state
windows - an array of window identifiers related to this message state

...

=head1 AUTHOR

David Ihnen, C<< <davidihnen at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-replay at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Replay>.  I will be notified, and then you'll automatically be notified of progress on your bug as I make changes .

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Replay

You can also look for information at:

https://github.com/DavidIAm/Replay

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


