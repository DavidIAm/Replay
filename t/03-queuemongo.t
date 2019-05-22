package Test::Replay::AWSQueue::Mongo::Filesystem;

use lib 't/lib';

use base qw/Replay::Test Test::Class/;
use JSON;
use YAML;
use File::Slurp;
use Test::Most;
our $REPLAY_TEST_CONFIG =  $ENV{REPLAY_TEST_CONFIG};

plan skip_all => 'REPLAY_TEST_CONFIG Env var not present '
     unless ($REPLAY_TEST_CONFIG );

sub t_environment_reset : Test(startup => 2) {
    my $self   = shift;
  
    my $replay = $self->{replay};
    `rm -rf $self->{storedir}`;
    ok !-d $self->{storedir};
    ok -f $self->{idfile};
    $replay->storageEngine->engine->db->drop;
}

sub a_replay_config : Test(startup => 4) {
    my $self = shift;
    $self->{awsconfig} = YAML::LoadFile($REPLAY_TEST_CONFIG);
    ok exists $self->{awsconfig}->{Replay}->{awsIdentity}->{access};
    ok exists $self->{awsconfig}->{Replay}->{awsIdentity}->{secret};
    ok exists $self->{awsconfig}->{Replay}->{snsService};
    ok exists $self->{awsconfig}->{Replay}->{sqsService};
    $self->{idfile}   = $REPLAY_TEST_CONFIG;
    $self->{storedir} = '/tmp/testscript-03-' . $ENV{USER};
    $self->{config}   = {
        timeout       => 400,
        stage         => 'testscript-03-' . $ENV{USER},
        StorageEngine => {
            Mode => 'Mongo',
            User =>  $self->{awsconfig}->{Mongo}->{user}, 
            Pass => $self->{awsconfig}->{Mongo}->{pass},
        },
        WORM => {
            Directory => "./log",
        },
        EventSystem => {
            Mode        => 'AWSQueue',
            awsIdentity => $self->{awsconfig}->{Replay}->{awsIdentity},
            snsService  =>  $self->{awsconfig}->{Replay}->{snsService},
            sqsService  =>  $self->{awsconfig}->{Replay}->{sqsService},
        },
        Defaults      => { ReportEngine => 'Filesystemtest' },
        ReportEngines => [{ Mode =>'Filesystem',
                            Root => $self->{storedir},
                            Name => 'Filesystemtest',
                            Access => 'public' } ]

    };
}

sub alldone : Test(teardown) {
}

Test::Class->runtests();
