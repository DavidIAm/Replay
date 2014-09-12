package Replay::BaseBusinessRule;

use Moose;
use Carp qw/croak/;

our $VERSION = '0.02';

has eventSystem => (is => 'ro', isa => 'Replay::EventSystem',);

# mapper
# [string]
has name => (is => 'ro', required => 1,);

# [string]
has version => (is => 'ro', isa => 'Str', default => '1',);

# [boolean] function match ( message )
sub match {
    croak 'stub, implement match';
}

# [timeWindowIdentifier] function window ( message )
sub window {
    my ($self, $message) = @_;

    # probably going to do soemthing with ->effectiveTime or ->receivedTime
    return 'alltime';
}

# [list of Key=>message pairs] function key_value_set ( message )
sub key_value_set {
    croak 'stub, implement key_value_set';
}

# storage
# [ compareFlag(-1,0,1) ] function compare ( messageA, messageB )
sub compare {
    return 0;
}

# reducer
# [arrayRef of messages] function reduce (key, arrayref of messages)
sub reduce {
    croak 'stub, implement reduce';
}

# bureaucrat
# [diff report] function fullDiff ( ruleA, Version, ruleB, Version )
has fullDiff => (is => 'ro', isa => 'CodeRef', required => 0,);

# clerk
# [formatted Report] function delivery ( rule, [ keyA => arrayrefOfMessage, ... ] )
# [formatted summary] function summary ( rule, [ keyA => arrayrefOfMessage, ... ] )
has delivery => (is => 'ro', isa => 'CodeRef', required => 0,);
has summary  => (is => 'ro', isa => 'CodeRef', required => 0,);

1;

__END__

=pod

=head1 NAME

Replay::BaseBusinessRule

=head1 VERSION

Version 0.01

=head1 SYNOPSIS

Business rule base class.  Inherit business rules from this.

package TESTRULE;

use Replay::BusinessRule 0.02;
use Replay::IdKey 0.02;
use Moose;
extends 'Replay::BusinessRule';
use List::Util qw//;

has '+name' => (default => __PACKAGE__,);

override match => sub {
    my ($self, $message) = @_;
    return $message->{is_interesting};
};

override key_value_set => sub {
    my ($self, $message) = @_;
    my @keyvalues = ();
    foreach my $key (keys %{$message}) {
        next unless 'ARRAY' eq ref $message->{$key};
        foreach (@{ $message->{$key} }) {
            push @keyvalues, $key, $_;
        }
    }
    return @keyvalues;
};

override compare => sub {
    my ($self, $aa, $bb) = @_;
    return ($aa || 0) <=> ($bb || 0);
};

override reduce => sub {
    my ($self, $emitter, @state) = @_;
    my $response = List::Util::reduce { $a + $b } @state;
};


=head1 SUBROUTINES/METHODS

=head2 name()

return the name of this rule

=head2 version()

return the version of this rule

=head2 match(message)

returns whether or not this message is interesting to this rule, as efficiently
as possible

=head2 key_value_set(message)

return a list of key => atom => key => atom reflecting the keys and atoms that 
will form the state

=head2 compare( atomA, atomB )

Sort subroutine - return -1, 0, or 1 depending on how these two atoms compare

Use for making particluar atoms adjacent for easy comparison.

=head2 reduce( emitter, atoms... )

Emit any messages using the emitter.

return the new list of atoms for the new canonical atoms for this state.

=head2 window

figure out what the window identifier is for this particular message

=head2 _build_eventSystem

=head2 _build_storageEngine

=head2 _build_reducer

=head2 _build_mapper

=head2 _build_worm

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
