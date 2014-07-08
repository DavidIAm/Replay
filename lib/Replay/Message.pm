package Replay::Message;

use Moose;
use MooseX::Storage;
use MooseX::MetaDescription::Meta::Trait;
use Time::HiRes qw/gettimeofday/;
use Data::UUID;

our $VERSION = '0.01';

extends 'Replay::Message::Base';
with Storage(format => 'JSON');

=pod 

Documentation
 
=cut

has messageType => (
    is          => 'ro',
    isa         => 'Str',
    required    => 1,
    init_arg    => 'messageType',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'envelope' },
);
has message => (
    is          => 'ro',
    required    => 0,
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'envelope' },
);
has program => (
    is          => 'ro',
    isa         => 'Str',
    required    => 0,
    init_arg    => 'program',
    predicate   => 'has_program',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'envelope' },
);
has function => (
    is          => 'ro',
    isa         => 'Str',
    required    => 0,
    init_arg    => 'function',
    predicate   => 'has_function',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'envelope' },
);
has line => (
    is          => 'ro',
    isa         => 'Str',
    required    => 0,
    init_arg    => 'line',
    predicate   => 'has_line',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'envelope' },
);
has effectiveTime => (
    is          => 'ro',
    isa         => 'Str',
    required    => 0,
    init_arg    => 'effectiveTime',
    predicate   => 'has_effective_time',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'envelope' },
);
has createdTime => (
    is          => 'ro',
    isa         => 'Str',
    required    => 0,
    init_arg    => 'createdTime',
    predicate   => 'has_created_time',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'envelope' },
    builder     => '_now'
);
has receivedTime => (
    is          => 'ro',
    isa         => 'Str',
    required    => 0,
    init_arg    => 'receivedTime',
    predicate   => 'has_recieved_time',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'envelope' },
    builder     => '_now'
);

has uuid => (
    is          => 'ro',
    isa         => 'Str',
    required    => 0,
    init_arg    => 'receivedTime',
    builder     => '_build_uuid',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'envelope' },
);

sub marshall {
    my $self     = shift;
    my $envelope = Replay::Message::Envelope->new(
        messsage    => $self,
        messageType => $self->messageType,
        uuid        => $self->uuid,
        ($self->has_program        ? (program        => $self->program)       : ()),
        ($self->has_function       ? (function       => $self->function)      : ()),
        ($self->has_line           ? (line           => $self->line)          : ()),
        ($self->has_effective_time ? (effective_time => $self->effectiveTime) : ()),
        ($self->has_created_time   ? (created_time   => $self->createdTime)   : ()),
        ($self->has_received_time  ? (received_time  => $self->receivedTime)  : ()),
    );
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

=head1 NAME

Replay::Message - The default message form for the Replay system

=head1 VERSION

Version 0.01

=head1 SYNOPSIS

the basic message functionality, providnig the serialization
routines and patterns for making a Replay Message

=head1 SUBROUTINES/METHODS

=head2 marshall ($message)

use the state information provided by the construction to create a structure suitable for serializing

=head2 _now

the current fractional second epoch time

=head2 _build_uuid

builder for getting the object with which uuids are created

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

1;
