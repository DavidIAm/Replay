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

    eval "require $class";

    return $class;
}

#__PACKAGE__->meta->make_immutable;

1;
