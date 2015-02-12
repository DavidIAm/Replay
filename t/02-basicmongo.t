package Test::Replay::AWSQueue::Mongo::Filesystem;

use lib 't/lib';

use base qw/Replay::Test/;

sub t_environment_reset : Test(startup) {
    my $self   = shift;
    my $replay = $self->{replay};
    `rm -rf $self->storedir`;
    $replay->storageEngine->engine->db->drop;
}

sub a_replay_config : Test(startup) {
    my $self = shift;
    $self->{storedir} = '/tmp/testscript-02-' . $ENV{USER};
    $self->{config}   = {
        timeout       => 40,
        stage         => 'testscript-02-' . $ENV{USER},
        StorageEngine => {
            Mode      => 'Mongo',
            MongoUser => 'replayuser',
            MongoPass => 'replaypass',
        },
        EventSystem   => { Mode => 'Null' },
        ReportEngine =>
            { Mode => 'Filesystem', reportFilesystemRoot => $self->{storedir}, },
    };
}

sub alldone : Test(teardown) {
}

Test::Class->runtests();

