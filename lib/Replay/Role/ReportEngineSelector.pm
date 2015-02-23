package Replay::Role::ReportEngineSelector;

use Replay::Role::ReportEngine;

use Moose::Role;
use English qw/-no_match_vars/;
use Carp qw/croak/;

requires qw(select);

has config => (is => 'ro', isa => 'HashRef[Item]', required => 1,);

has ruleSource  => (is => 'ro', isa => 'Replay::RuleSource',  required => 1,);
has eventSystem => (is => 'ro', isa => 'Replay::EventSystem', required => 1,);

has availableReportEngines => (
    is      => 'ro',
    isa     => 'HashRef[Replay::Role::ReportEngine]',
    builder => '_build_availableReportEngines',
    lazy    => 1,
);

has defaultReportEngine => (
    is      => 'ro',
    isa     => 'Replay::Role::ReportEngine',
    builder => '_build_defaultReportEngine',
    lazy    => 1,
);

sub _build_availableReportEngines
{    ## no critic (ProhibitUnusedPrivateSubroutines)
    my $self            = shift;
    my $hash_of_engines = {};

    foreach my $engine (keys %{ $self->config->{ReportEngines} }) {

        $hash_of_engines->{$engine} = $self->mode_class($engine)->new(
            config => {
                %{ $self->config },
                StorageEngine => $self->config->{ReportEngines}{$engine}
            },
            ruleSource  => $self->ruleSource,
            eventSystem => $self->eventSystem,
        );
    }
    return $hash_of_engines;
}

sub _build_defaultReportEngine
{    ## no critic (ProhibitUnusedPrivateSubroutines)
    my $self    = shift;
    my $default = $self->availableReportEngines()
        ->{ $self->config->{Defaults}->{ReportEngine} };
    unless ($default) {
        croak 'No ReportEngine '
            . $self->config->{Defaults}->{ReportEngine}
            . ' defined';
    }
    return $default;
}

sub all_engines {
    my ($self) = @_;
    return values %{ $self->availableReportEngines };
}

sub mode_class {      ## no critic (ProhibitUnusedPrivateSubroutines)
    my ($self, $mode) = @_;
    if (not $mode) {
        croak q(No ReportMode?);
    }
    my $class = 'Replay::ReportEngine::' . $mode;
#    try {
        eval "require $class";
#            or croak qq(error requiring class $class : ) . $EVAL_ERROR;
#    }
#    catch {
#        confess q(No such report engine mode available )
#            . $mode
#            . " --> $_";
#    };
    return $class;
}

1;

=pod

=head1 NAME

Replay::Role::ReportEngineSelector

=head1 VERSION

Version 0.03

=head1 SYNOPSIS

Defines the interface for an implimentation of a report engine selector

package engineuser;

 my $selector = new DEFAULTSELECTOR(
    ruleSouce => $rulesourceinstance,
    eventSystem => $eventsysteminstance,
    config => { ReportEngines => {
       keya => { configuration }
       keyb => { configuration }
    },
    Defaults => { ReportEngine => 'keya' }
  });

my $reportEngine = $selector->select('thisdisposition');

package DEFAULTSELECTOR;

use Moose;
with 'Replay::Role::ReportEngineSelector';

sub select {
  my ($self, $disposition) = @_;
  return $self->defaultReportEngine;
}

=head1 SUBROUTINES/METHODS

=head2 _build_availableReportEngines

return a hashref with key=>instance for all the available report engines

=head2 _build_defaultReportEngine

return the instance for the configured default report engine

=head2 all_engines

returns an unordered list of all of the known engines

=head2 mode_class

return the class name for this mode.  Make sure its loaded in perl too.

=head1 IMPLIMENTOR METHODS

=head2 select( disposition )

return the report engine instance to use for this disposition

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
