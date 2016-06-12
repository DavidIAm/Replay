package Test::Replay::RabbitMemory;

use base qw/Test::Replay/;

use lib 'lib';

=pod
sub t_environment_reset : Test(startup) {
    use Replay;
    Replay::ReportEngine->new(
        config => {
            ReportEngine => {
                Mode      => 'Mongo',
                Mode      => 'Mongo',
                MongoUser => 'replayuser',
                MongoPass => 'replaypass',
            },
        },
        rule => []
        )
        ->engine->collection(Replay::IdKey->new(name => 'TESTRULE', version => 1))
        ->remove();
}
=cut

sub t_environment_reset : Test(startup) {
  my $self = shift;
   `rm -rf $self->{storedir}`;

}

sub a_replay_config : Test(startup) {
    my $self = shift;
    $self->{storedir} = '/tmp/testscript-07-' . $ENV{USER};
    $self->{config} = {
        stage       => 'tests',
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
        Defaults      => { ReportEngine => 'Filesystem' },
        ReportEngines => [
            {
                Name => 'Filesystem',
                Mode => 'Filesystem',
                Root => $self->{storedir},
            }
        ],
    };
}

sub alldone : Test(teardown) {
}

Test::Class->runtests();
