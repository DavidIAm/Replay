package Test::Replay::ReportMongo;

use base qw/Replay::Test/;
use File::Temp qw/tempdir/;

sub t_environment_reset : Test(startup) {
    my $self   = shift;
    my $replay = $self->{replay};
    $replay->reportEngine->engine->db->drop;
}

sub a_replay_config : Test(startup) {
    my $self = shift;
    $self->{config} = {
        Defaults      => { ReportEngine => 'MongoTest' },
        stage         => 'testscript-08-' . $ENV{USER},
        EventSystem   => { Mode         => 'Null', },
        StorageEngine => { Mode         => 'Memory', },
        ReportEngines => [
            {   Mode   => 'Filesystem',
                Root   => tempdir,
                Name   => 'Filesystemtest',
                Access => 'public'
            },
            {   Mode      => 'Mongo',
                User => 'replayuser',
                Name      => 'MongoTest',
                Pass => 'replaypass'
            },
        ],
        timeout => 10,
    };
}

sub alldone : Test(teardown) {
}

Test::Class->runtests();

