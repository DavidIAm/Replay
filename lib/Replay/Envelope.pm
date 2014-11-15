package Replay::Envelope;

use Data::Dumper;
use Moose::Role;
use Time::HiRes qw/gettimeofday/;
use Moose::Util qw(apply_all_roles);
use Data::UUID;

our $VERSION = '0.02';

has Replay => (
    is          => 'ro',
    isa         => 'Str',
    default     => '20140727',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'envelope' },
);

has MessageType => (
    is          => 'ro',
    isa         => 'Str',
    required    => 1,
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'envelope' },
);
has Message => (
    is          => 'ro',
    isa         => 'Str|HashRef',
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
    builder     => 'assume_effective_time',
);
has CreatedTime => (
    is          => 'ro',
    isa         => 'Str',
    predicate   => 'has_created_time',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'envelope' },
    builder     => '_now',
);
has ReceivedTime => (
    is          => 'ro',
    isa         => 'Str',
    predicate   => 'has_received_time',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'envelope' },
    builder     => '_now',
);

has UUID => (
    is          => 'ro',
    isa         => 'Str',
    builder     => '_build_uuid',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'envelope' },
);

around BUILDARGS => sub {
    my $orig  = shift;
    my $class = shift;
    my %args  = 'HASH' eq ref $_[0] ? %{ $_[0] } : @_;
    $class->meta->make_mutable;
    my %attributes = map { $_->{name} => $_ } $class->meta->get_all_attributes;

    foreach (keys %args) {
        next if exists $attributes{$_};

        my $newattr = $class->meta->add_attribute(
            $_ => (
                is          => 'ro',
                isa         => 'Item',
                traits      => ['MooseX::MetaDescription::Meta::Trait'],
                description => { layer => 'message' }
            )
        );
        apply_all_roles($newattr, 'MooseX::MetaDescription::Meta::Trait');
        $args{EXTRA}{$_} = $args{$_};
    }
    $class->meta->make_immutable;
    return $class->$orig(%args);
};

sub marshall {
    my $self       = shift;
    my $buffer     = q();
    my $row        = 1;
    my $layers     = {};
    my %attributes = map { $_->{name} => $_ } $self->meta->get_all_attributes;
    foreach my $attr (sort { $a cmp $b } keys %attributes) {

        my $field = $attributes{$attr};

        do {
            warn "NO SUCH ATTRBUTE $attr IN META OF "
                . ref($self) . " - "
                . Dumper ref $attributes{$attr}
                and next;
        } unless defined $field;
        my $thislayer
            = ($field->can('description') ? $field->description->{layer} : '')
            || 'sloppy';

        my $node = $layers->{$thislayer} ||= {};

        my $value = $self->$attr
            ; #$field->can('associated_role') ? $field->associated_role->get_value($self) : $field->get_value($self);
        next if not defined $value;

        $node->{$attr} = $value;
    }
    my $curmessage = $layers->{envelope}{Message} ||= {};
    %{$curmessage} = (%{$curmessage}, %{ $layers->{message} || {} });
    return $layers->{envelope};
}

sub _now {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my $self = shift;
    return +gettimeofday;
}

sub _build_uuid {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my $self = shift;
    my $ug   = Data::UUID->new;
    return $ug->to_string($ug->create());
}

has Timeblocks => (
    is          => 'rw',
    isa         => 'ArrayRef',
    predicate   => 'has_timeblocks',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'envelope' },
);
has Ruleversions => (
    is          => 'rw',
    isa         => 'ArrayRef[HashRef]',
    predicate   => 'has_ruleversions',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'envelope' },
);
has Windows => (
    is          => 'rw',
    isa         => 'ArrayRef[Str]',
    predicate   => 'has_windows',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'envelope' },
);

sub assume_effective_time {
    my $self = shift;
    return $self->ReceivedTime || $self->_now;
}

=pod

1;

__END__

=pod

=head1 NAME

Replay::Envelope - General replay message envelope 

=head1 VERSION

Version 0.01

=cut

=head1 SYNOPSIS

This is a message data type envelop used for most messages on the derived channel

effectiveTime - the time this event refers to
receivedTime - the time the message entered the system
createdTime - the time the message was created originally
Timeblocks - an array of the time block identifiers related to this message state
Ruleversions - an array of { name:, version: } objects related to this message state
Windows - an array of window identifiers related to this message state

=head1 FIELDS

=head2 Replay => The version of this replay message
=head2 Message => The message will go here
=head2 Program => What program generated this message
=head2 Function => What function were we in when this message was created
=head2 Line => What line of the application created this message
=head2 EffectiveTime => The time this message is relevant to
=head2 CreatedTime => The time at which this message was created
=head2 ReceivedTime => The time at which this message was received (probably by WORM)
=head2 UUID => The unique identifier for this message
=head2 Timeblocks => The time blocks from which this message is derived
=head2 Ruleversions => The rules (and their versions) from which this message is derived
=head2 Windows => The window blocks from which this message is derived

=head1 METHODS

=head2 marshall

Collects the elements of the message that form our Logistics Message

=head2 _now

Accessor for the current time

=head2 _build_uuid

Builder for instantiating the uuid object that creates new UUIDs

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

