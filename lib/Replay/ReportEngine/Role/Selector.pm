package Replay::ReportEngine::Role::Selector;

use Replay::Role::ReportEngine;

use Moose::Role;
use Moose::Util::TypeConstraints;
use English qw/-no_match_vars/;
use Carp qw/croak/;

requires qw(select);

has config => ( is => 'ro', isa => 'HashRef[Item]', required => 1, );

has ruleSource  => ( is => 'ro', isa => 'Replay::RuleSource',  required => 1, );
has eventSystem => ( is => 'ro', isa => 'Replay::EventSystem', required => 1, );
has storageEngine =>
  ( is => 'ro', isa => 'Replay::StorageEngine', required => 1, );

role_type WithReportEngine => { role => 'Replay::Role::ReportEngine' };

has availableReportEngines => (
    is      => 'ro',
    isa     => 'ArrayRef[WithReportEngine]',
    builder => '_build_availableReportEngines',
    lazy    => 1,
);

has defaultReportEngine => (
    is      => 'ro',
    isa     => 'WithReportEngine',
    builder => '_build_defaultReportEngine',
    lazy    => 1,
);

sub _build_availableReportEngines {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my $self            = shift;
    my $list_of_engines = [];

    foreach my $engine ( @{$self->config->{ReportEngines} } ) {
#      confess "INVALID ENGINE" unless defined $engine->{Name};

        push @{$list_of_engines}, my $d = $self->mode_class($engine->{Mode})->new(
            config      => $self->config,
            thisConfig => $engine,
            ruleSource  => $self->ruleSource,
            eventSystem => $self->eventSystem,
        );
        confess "WHAT IS $d" . $d->dump(1) unless $d->does('Replay::Role::ReportEngine');
    }
    return $list_of_engines;
}

sub _build_defaultReportEngine { ## no critic (ProhibitUnusedPrivateSubroutines)
    my $self    = shift;
    my $default = (grep { $_->Name eq $self->config->{Defaults}->{ReportEngine} } @{$self->availableReportEngines()})[0];
    
use Data::Dumper;    

warn("<-----JSP default =".$self->config->{Defaults}->{ReportEngine});
    unless ($default) {
      use Data::Dumper;
        croak 'No ReportEngine '
          . $self->config->{Defaults}->{ReportEngine}
          . ' defined' . Dumper $self->availableReportEngines;
    }
    return $default;
}

sub all_engines {
    my ($self) = @_;
    return values %{ $self->availableReportEngines };
}

sub mode_class {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my ( $self, $mode ) = @_;
    if ( not $mode ) {
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
