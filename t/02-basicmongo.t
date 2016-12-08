package Test::Replay::AWSQueue::Mongo::Filesystem;

use lib 't/lib';

use base qw/Replay::Test/;

sub t_environment_reset : Test(startup) {
    my $self   = shift;
    my $replay = $self->{replay};
    $replay->storageEngine->engine->db->drop;
}

sub a_replay_config : Test(startup) {
    my $self = shift;
    $self->{config}   = {
        timeout       => 40,
        stage         => 'testscript-02-' . $ENV{USER},
        WORM          => { Directory => tempdir },
        StorageEngine => {
            Mode      => 'Mongo',
            MongoUser => 'replayuser',
            MongoPass => 'replaypass',
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

