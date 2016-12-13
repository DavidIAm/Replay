package Test::Replay::Null::Mongo::Filesystem;

use lib 't/lib';

use base qw/Replay::Test/;

sub t_environment_reset : Test(shutdown) {
    my $self   = shift;
    $self->{replay}->storageEngine->engine->db->drop;
    1;
}

sub a_replay_config : Test(startup) {
    my $self = shift;
    $self->{config}   = {
        timeout       => 40,
        stage         => 'testscript-02-' . $ENV{USER},
        WORM          => { Directory => tempdir },
        StorageEngine => {
            Mode      => 'Mongo',
            User => 'replayuser',
            Pass => 'replaypass',
        },
        EventSystem   => { Mode         => 'Null' },
        Defaults      => { ReportEngine => 'Filesystemtest' },
        ReportEngines => [{ Mode =>'Filesystem',
                            Root => tempdir,
                            Name => 'Filesystemtest',
                            Access => 'public' } ]
    };
}

sub alldone : Test(teardown) {
}

Test::Class->runtests();

