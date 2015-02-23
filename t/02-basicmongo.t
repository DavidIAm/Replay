package Test::Replay::AWSQueue::Mongo::Filesystem;

use lib 't/lib';

use Test::Most qw/bail/;

use base qw/Replay::Test/;

sub t_environment_reset : Test(startup => 1) {
    my $self   = shift;
    my $replay = $self->{replay};
    `rm -rf $self->{storedir}`;
    ok $replay->storageEngine->engine->db->drop->{ok};
}

sub a_replay_config : Test(startup) {
    my $self = shift;
    $self->{storedir} = '/tmp/testscript-02-' . $ENV{USER};
    $self->{config}   = {
        timeout       => 10,
        stage         => 'testscript-02-' . $ENV{USER},
        StorageEngine => {
            Mode      => 'Mongo',
            User => 'replayuser',
            Pass => 'replaypass',
        },
        EventSystem   => { Mode => 'Null' },
        Defaults      => { ReportEngine => 'Memory' },
        ReportEngines => { Memory => { Mode => 'Memory' } },
    };
}

sub alldone : Test(teardown) {
}

__PACKAGE__->runtests();

1;
