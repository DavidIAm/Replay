package Replay::ReportEngine::Selector;
use Moose;
with qw(Replay::ReportEngine::Role::Selector);

our $VERSION = '0.04';

sub select_engine {
    my ( $self, $idkey ) = @_;

  # TODO: Some other selector would use this disposition to change where it
  # goes
  # my $disposition = $self->ruleSource->by_idkey($idkey)->report_disposition;
    return $self->defaultReportEngine;
}

1;
