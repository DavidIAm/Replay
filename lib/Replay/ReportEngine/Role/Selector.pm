package Replay::ReportEngine::Role::Selector;

use Replay::Role::ReportEngine;

use Moose::Role;
use Try::Tiny;
use Moose::Util::TypeConstraints;
use English qw/-no_match_vars/;
use Data::Dumper;
use Carp qw/croak/;

requires qw(select_engine);

our $VERSION = '0.04';

has config => ( is => 'ro', isa => 'HashRef[Item]', required => 1, );

has ruleSource => ( is => 'ro', isa => 'Replay::RuleSource', required => 1, );
has eventSystem =>
    ( is => 'ro', isa => 'Replay::EventSystem', required => 1, );
has storageEngine =>
    ( is => 'ro', isa => 'Replay::StorageEngine', required => 1, );

role_type WithReportEngine => { role => 'Replay::Role::ReportEngine' };

has availableReportEngines => (
    is      => 'ro',
    isa     => 'ArrayRef[WithReportEngine]',
    builder => '_build_available_report_engines',
    lazy    => 1,
);

has defaultReportEngine => (
    is      => 'ro',
    isa     => 'WithReportEngine',
    builder => '_build_default_report_engine',
    lazy    => 1,
);

sub _build_available_report_engines
{    ## no critic (ProhibitUnusedPrivateSubroutines)
    my $self            = shift;
    my $list_of_engines = [];

    foreach my $engine ( @{ $self->config->{ReportEngines} } ) {

        #      confess 'INVALID ENGINE' unless defined $engine->{Name};

        push @{$list_of_engines},
            my $d = $self->mode_class( $engine->{Mode} )->new(
            config      => $self->config,
            thisConfig  => $engine,
            ruleSource  => $self->ruleSource,
            eventSystem => $self->eventSystem,
            );
        confess 'WHAT IS ' . $d . $d->dump(1)
            if !$d->does('Replay::Role::ReportEngine');
    }
    return $list_of_engines;
}

sub _build_default_report_engine
{    ## no critic (ProhibitUnusedPrivateSubroutines)
    my $self = shift;
    my $default
        = ( grep { $_->Name eq $self->config->{Defaults}->{ReportEngine} }
            @{ $self->availableReportEngines() } )[0];
    if ( !$default ) {
        croak 'No ReportEngine '
            . $self->config->{Defaults}->{ReportEngine}
            . ' defined'
            . Dumper $self->availableReportEngines;
    }
    return $default;
}

sub all_engines {
    my ($self) = @_;
    return values %{ $self->availableReportEngines };
}

sub mode_class {
    my ( $self, $mode ) = @_;
    if ( not $mode ) {
        croak q(No ReportMode?);
    }
    my $class = 'Replay::ReportEngine::' . $mode;

    my $path = $class . '.pm';
    $path =~ s{::}{/}gxsm;
    if ( eval { require $path } ) {
    }
    else {
        croak $EVAL_ERROR;
    }

    return $class;
}

1;

__END__

=pod

=head1 NAME

Replay::ReportEngine::Role::Selector - selector for report engine

=head1 VERSION

Version 0.01

=head1 SYNOPSIS

 package DefaultReportEngineSelector;
 
 use Moose;
 with qw/Replay::ReportEngine::Role::Selector/;
 
 sub select_engine {
   my ($self, $idkey) = @_;
   return $self->defaultReportEngine;
 }

=head1 DESCRIPTION

This is the role definition used by the report engine selector
implementation

=head1 SUBROUTINES/METHODS

All role consumers must implement the following

=head2 select_engine - select engine based on idkey

select_engine($idkey)

This uses whatever logic is relevant to transform a data location on which
the report is being generated (idkey) to which report engine should be
used for it.

The intention is that this is used to change between internal and
external report rules, or different sorts of availability as relevant
to the business case being pursued

=head1 REPORT ENGINE SELECTOR INTERFACE

The utilizers of report engine selector roles can use these API points

=head2 all_engines(idkey)

returns a list of all of the actively configured report engines the
instance knows about

=head1 INTERNAL METHODS

=head2 mode_class(mode)

transforms a configuration Mode into a class name for loading

=head1 AUTHOR

David Ihnen, C<< <davidihnen at gmail.com> >>

=head1 CONFIGURATION AND ENVIRONMENT

Implied by context

=head1 DIAGNOSTICS

nothing to say here

=head1 DEPENDENCIES

Nothing outside the normal Replay world

=head1 INCOMPATIBILITIES

Nothing to report

=head1 BUGS AND LIMITATIONS

Please report any bugs or feature requests to
C<bug-replay at rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Replay>.  I will be
notified, and then you\'ll automatically be notified of progress on your
bug as I make changes.

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
under the terms of the the Artistic License (2.0). You may obtain a copy
of the full license at:

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
patent license to make, have made, use, offer to sell, sell, import
and otherwise transfer the Package with respect to any patent claims
licensable by the Copyright Holder that are necessarily infringed by the
Package. If you institute patent litigation (including a cross-claim or
counterclaim) against any party alleging that the Package constitutes
direct or contributory patent infringement, then this Artistic License
to you shall terminate on the date that such litigation is filed.

Disclaimer of Warranty: THE PACKAGE IS PROVIDED BY THE COPYRIGHT HOLDER
AND CONTRIBUTORS 'AS IS' AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES.
THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE, OR NON-INFRINGEMENT ARE DISCLAIMED TO THE EXTENT PERMITTED
BY YOUR LOCAL LAW. UNLESS REQUIRED BY LAW, NO COPYRIGHT HOLDER OR
CONTRIBUTOR WILL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, OR
CONSEQUENTIAL DAMAGES ARISING IN ANY WAY OUT OF THE USE OF THE PACKAGE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut

1;    # End of Replay


