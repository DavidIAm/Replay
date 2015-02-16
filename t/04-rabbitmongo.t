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
    $self->{storedir} = '/tmp/testscript-04-' . $ENV{USER};
    $self->{config}   = {
        timeout       => 400,
        stage         => 'testscript-04-' . $ENV{USER},
        StorageEngine => {
            Mode      => 'Mongo',
            MongoUser => 'replayuser',
            MongoPass => 'replaypass',
        },
        EventSystem => {
            Mode     => 'RabbitMQ',
            RabbitMQ => {
                host    => 'localhost',
                options => {
                    port     => '5672',
                    user     => 'testuser',
                    password => 'testpass',

                    #            user    => 'replay',
                    #            pass    => 'replaypass',
                    #vhost   => 'replay',
                    vhost       => '/testing',
                    timeout     => 30,
                    tls         => 1,
                    heartbeat   => 1,
                    channel_max => 0,
                    frame_max   => 131072
                },
            },
        },
        ReportEngine  => { Mode => 'Memory' }
    };
}

sub alldone : Test(teardown) {
}

Test::Class->runtests();
