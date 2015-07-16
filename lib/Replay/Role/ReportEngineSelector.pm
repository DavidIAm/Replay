package Replay::Role::ReportEngineSelector;

use Replay::Role::ReportEngine;

use Moose::Role;
use English qw/-no_match_vars/;
use Carp qw/croak/;

requires qw(select);

has config => (is => 'ro', isa => 'HashRef[Item]', required => 1,);

has ruleSource  => (is => 'ro', isa => 'Replay::RuleSource',  required => 1,);
has eventSystem => (is => 'ro', isa => 'Replay::EventSystem', required => 1,);
has storageEngine =>
    (is => 'ro', isa => 'Replay::StorageEngine', required => 1,);

has availableReportEngines => (
    is      => 'ro',
    isa     => 'HashRef[Object]',
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

   unless($classname->does('Replay::Role::ReportEngine')){
       my  $classname = $self->mode_class($engine);
        croak $classname.q( -->Must use the Replay::Role::ReportEngin 'Role' );
        
    }    
        $hash_of_engines->{$engine} = $self->mode_class($engine)->new(
            config      => $self->config,
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
