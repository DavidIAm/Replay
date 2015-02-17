package Test::Replay::ReportMongo;

use lib 't/lib';

use Test::Most qw/bail/;

use base qw/Replay::Test/;

sub t_environment_reset : Test(startup) {
    my $self   = shift;
    my $replay = $self->{replay};
    $replay->reportEngine->engine(Replay::IdKey->new(name => 'TESTRULE', version => 1))->db->drop;
}

sub a_replay_config : Test(startup) {
    my $self = shift;
    $self->{config} = {
        stage         => 'testscript-08-' . $ENV{USER},
        EventSystem   => { Mode => 'Null', },
        StorageEngine => { Mode => 'Memory', },
        Defaults      => { ReportEngine => 'Mongo' },
        ReportEngines => {
            Mongo => { Mode => 'Mongo', User => 'replayuser', Pass => 'replaypass', },
        },
        timeout => 10,
    };
}

sub alldone : Test(teardown) {
}

Test::Class->runtests();
