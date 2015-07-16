package Replay::ReportEngine::Selector;
use Moose;
with qw(Replay::Role::ReportEngineSelector);

sub select {
  my ($self, $disposition) = @_;
  return $self->defaultReportEngine;
}

1;
