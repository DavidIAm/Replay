package Replay::BusinessRule;
use Carp qw/croak carp/;
use Moose;
with 'Replay::Role::BusinessRule';

has eventSystem => (is => 'ro', isa => 'Replay::EventSystem',);
has reportEngine=> (is => 'ro', isa => 'Str',);
has delivery => (is => 'ro', isa => 'CodeRef', required => 0,);
# mapper
# [string]
has name => (is => 'ro', required => 1,);

# [string]
has version => (is => 'ro', isa => 'Str', default => '1',);



has report_disposition => (is => 'ro', default => 0);

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

our $VERSION = '0.02';

1;

__END__

=pod

=head1 NAME

Replay::BusinessRule

=head1 VERSION

Version 0.01

=head1 SYNOPSIS

Deprecated.  use role Replay::Role::BusinessRule instead

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
