package Replay::ReportEngine::Selector;
use Moose;
with qw(Replay::Role::ReportEngineSelector);

sub select {
    my ( $self, $idkey ) = @_;

    # TODO: Some other selector would use this disposition to change where it
    # goes
    # my $disposition = $self->ruleSource->by_idkey($idkey)->report_disposition;
    return $self->defaultReportEngine;
}

1;
