package Replay::Janitor;

use Moose;
use Try::Tiny;
use English '-no_match_vars';
use Carp qw/croak/;
use Readonly;

our $VERSION = '0.01';

Readonly my $DEFAULT_INTERVAL => 90;

has config => ( is => 'ro', isa => 'HashRef[Item]', required => 1, );

has storageEngine =>
    ( is => 'ro', isa => 'Replay::StorageEngine', required => 1, );
has eventSystem =>
    ( is => 'ro', isa => 'Replay::EventSystem', required => 1, );

has interval => ( is => 'ro', builder => '_build_interval', lazy => 1 );

sub BUILD {
    my ($self) = @_;
    warn "Janitor is initializing";
    $self->eventSystem->register_timer(
        name     =>'janitor',
        interval => $self->interval,
        cb       => sub {
            warn "Janitor is reverting all expired locks";
            $self->storageEngine->revert_all_expired_locks();
            $self->storageEngine->reduce_all_inboxes();
        },
    );
}

sub _build_interval {
    my ($self) = @_;
    return $self->config->{Janitor}->{interval} || $DEFAULT_INTERVAL;
}

1;

__END__

=pod

=head1 NAME

Replay::Janitor

=head1 NAME

Replay::Janitor - the janitor component of the system to keep things clean

=head1 VERSION

Version 0.01

=head1 SYNOPSIS

 my $janitor = Replay::Janitor->new(
   eventSystem => $eventSystem,
   storageEngine => $storageEngine,
 );

 $eventSystem->run;

=head1 CONFIGURATION AND ENVIRONMENT

Implied by context

=head1 DESCRIPTION

The janitor periodically runs the revert_all_expired_locks function of the
storageEngine interface, to keep any lost pieces from being neglected.

=head1 SUBROUTINES/METHODS

=head2 BUILD

The moose setup/initializer function - it tells the event system that it
wants a repeating interval callback to be run.

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

Please report any bugs or feature requests to C<bug-replay at rt.cpan.org>,
or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Replay>.  I will be notified,
and then you'll automatically be notified of progress on your bug as I make
changes.

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

