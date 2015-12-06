package Test::Replay::ReportMongo;

use lib 't/lib';

use base qw/Replay::Test/;

sub t_environment_reset : Test(startup) {
    my $self   = shift;
    my $replay = $self->{replay};
    $replay->reportEngine->engine->db->drop;
}

sub a_replay_config : Test(startup) {
    my $self = shift;
    $self->{config} = {
        stage         => 'testscript-08-' . $ENV{USER},
        EventSystem   => { Mode => 'Null', },
        StorageEngine => { Mode => 'Memory', },
        Defaults      => { ReportEngine => 'MongoAlter' },
        ReportEngines => [
            {
                Name      => 'MongoAlter',
                Mode      => 'Mongo',
                User => 'replayuser',
                Pass => 'replaypass',
            },
            {
                Name      => 'FileBug',
                Mode      => 'Filesystem',
                Root => '/tmp/rpt',
            },
        ],
        timeout => 10,
    };
}

sub alldone : Test(teardown) {
}

Test::Class->runtests();

1;
