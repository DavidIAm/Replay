package Test::Replay::AWSQueue::Mongo::Filesystem;

use lib 't/lib';

use base qw/Replay::Test Test::Class/;
use JSON;
use File::Slurp;
use Test::Most;

sub t_environment_reset : Test(startup => 2) {
    my $self   = shift;
    my $replay = $self->{replay};
    `rm -rf $self->{storedir}`;
    ok !-d $self->{storedir};
    ok -f $self->{idfile};
    $replay->storageEngine->engine->db->drop;
}

sub a_replay_config : Test(startup => 2) {
    my $self = shift;
    $self->{identity} = from_json read_file('/etc/cargotel/testidentity');
    ok exists $self->{identity}{access};
    ok exists $self->{identity}{secret};
    $self->{idfile}   = '/etc/cargotel/testidentity';
    $self->{storedir} = '/tmp/testscript-03-' . $ENV{USER};
    $self->{config}   = {
        timeout       => 400,
        stage         => 'testscript-03-' . $ENV{USER},
        StorageEngine => {
            Mode      => 'Mongo',
            User => 'replayuser',
            Pass => 'replaypass',
        },
        EventSystem => {
            Mode        => 'AWSQueue',
            awsIdentity => $self->{identity},
            snsService  => 'https://sns.us-east-1.amazonaws.com',
            sqsService  => 'https://sqs.us-east-1.amazonaws.com',
        },
        Defaults      => { ReportEngine => 'Memory' },
        ReportEngines => { Memory => { Mode => 'Memory' } },
    };
}

sub alldone : Test(teardown) {
}

Test::Class->runtests();
