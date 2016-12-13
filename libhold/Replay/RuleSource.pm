package Replay::RuleSource;

use Moose;
use Replay::Message::RulesReady;
use Scalar::Util qw/blessed/;
use Replay::Types::Types;

our $VERSION = q(0.02);

# this is the default implimentation that is simple.  This needs to be
# different later.  The point of this layer is to instantiate and handle the
# various execution environments for a particular rule version.
has rules => (is => 'ro', isa => 'ArrayRef[BusinessRule]',);

has index => (is => 'rw', default => 0,);
has eventSystem => (is => 'ro', isa => 'Replay::EventSystem', required => 1);

sub next {    ## no critic (ProhibitBuiltinHomonyms)
    my ($self) = @_;
    my $i = $self->index;
    $self->index($self->index + 1);
    if ($#{ $self->rules } < $i) { $self->index(0) and return }
    return $self->rules->[$i];
}

sub first {
    my ($self) = @_;
    $self->index(0);
    return $self->rules->[ $self->index ];
}

sub by_idkey {
    my ($self, $idkey) = @_;
    if ($idkey && blessed $idkey && $idkey->can('name')) {
        return (grep { $_->name eq $idkey->name && $_->version eq $idkey->version }
                @{ $self->rules })[0];
    }
    confess("Called by_idkey without an idkey? ($idkey)");
}

1;

__END__

=pod

=head1 NAME

Replay::RuleSource - Provider of a set of objects of type Replay::BusinesRule

=head1 SYNOPSIS

my $source = new Replay::RuleSource( rules => [ $RuleInstance, $otherrule  ] );

=head1 DESCRIPTION

The purpose of this abstraction is to allow the dramatic scaling of these rules   Not everything needs to be in memory at the same time.

Current iteration takes an array of Business Rules.  Maybe its tied?  What other options do we have here?

=head1 SUBROUTINES/METHODS

=head2 next 

Deliver the next business rule.  Undef means the end of the list, which resets the pointer to the first.

=head2 first 

Reset the current rule pointer and deliver the first business rule

=head2 by_idkey 

The IDKey hash/object is used to identify particular rules.  Given a particular
IdKey state, this routine should return all of the rules that match it.  This is
expected to be a list of one or zero.

=head1 AUTHOR

David Ihnen, C<< <davidihnen at gmail.com> >>

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
1;
