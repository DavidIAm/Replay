package Replay::IdKey;

use Moose;
use MongoDB;
use MooseX::Storage;
use MongoDB::OID;
use Digest::MD5 qw/md5_hex/;

our $VERSION = '0.02';

has name => (
    is          => 'rw',
    isa         => 'Str',
    required    => 1,
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'message' },
);
has version => (
    is          => 'rw',
    isa         => 'Str',
    required    => 1,
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'message' },
);
has window => (
    is          => 'rw',
    isa         => 'Str',
    required    => 1,
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'message' },
);
has key => (
    is          => 'rw',
    isa         => 'Str',
    required    => 1,
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'message' },
);
has revision => (
    is          => 'rw',
    isa         => 'Str',
    default     => 'latest',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'message' },
);
has reportType => (
    is          => 'rw',
    isa         => 'Str',
    default     => 'Delivery',
);

with Storage('format' => 'JSON');

sub collection {
    my ($self) = @_;
    return 'replay-' . $self->name . $self->version;
}

sub parse_cubby {
    my ($class,  $cubby) = @_;
    my ($window, $key)   = $cubby =~ /^wind-(.+)-key-(.+)$/smix;
    return window => $window, key => $key;
}

sub window_prefix {
    my ($self) = @_;
    return 'wind-' . $self->window . '-key-';
}

sub cubby {
    my ($self) = @_;
    return $self->window_prefix . $self->key;
}

sub rule_spec {
    my ($self) = @_;
    return 'rule-' . $self->name . '-version-' . $self->version;
}

sub delivery {
    my ($self) = @_;
    return ref($self)->new(
        name       => $self->name,
        version    => $self->version,
        window     => $self->window,
        key        => $self->key,
        revision   => $self->revision,
        reportType => 'Delivery',
    );
}

sub summary {
    my ($self) = @_;
    return ref($self)->new(
        name     => $self->name,
        version  => $self->version,
        window   => $self->window,
        revision => $self->revision,
        reportType => 'Summary',
    );
}

sub globsummary {
  my ($self) = @_;
    return ref($self)->new(
        name     => $self->name,
        version  => $self->version,
        revision => $self->revision,
        reportType => 'GlobSummary',
    );
}

sub hash_list {
    my ($self) = @_;
    return %{ $self->marshall };
}

sub checkstring {
    my ($self) = @_;
    $self->name($self->name . q());
    $self->version($self->version . q());
    $self->window($self->window . q());
    $self->key($self->key . q());
    return;
}

sub hash {
    my ($self) = @_;
    $self->checkstring;
    return md5_hex($self->freeze);
}

sub marshall {
    my ($self) = @_;
    return {
        name    => $self->name,
        version => $self->version,
        window  => $self->window,
        key     => $self->key,
        ($self->revision ne 'latest' ? (revision => $self->revision) : ()),
    };
}

1;

__END__

=pod

=head1 NAME

Replay::IdKey - A data type that encapsulates the state of the movie

=head1 VERSION

Version 0.01

=head1 SYNOPSIS

Each state of the system exists in a hierarchy which at this time is defined as

name
version
window
key

=head1 SUBROUTINES/METHODS

=head2 collection

used to name the collection in which this part of the hierarchy will be found

=head2 window_prefix

The window based prefix for the cubby key

=head2 parse_cubby

static

translate a cubby name to a window => $window, key => $key sequence

=head2 cubby

The window-and-key part - where the document reflecting the state is found

=head2 rule_spec

the rule-and-version part - the particular business rule this state will be useing

=head2 hash_list

alias for marshall

=head2 checkstring

makes sure that all the fields are strings so that canonical freezing is consistent

=head2 hash

Provides an md5 sum that is distinct for this location

=head2 marshall

Arrange the fields in a list for passing to various other locations

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
