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

sub t_environment_reset : Test(startup=>2) {
  my $self = shift;
  
  
 
  
   `rm -rf $self->{storedir}`;

}

sub a_replay_config : Test(startup=>2) {
    my $self = shift;
    
    eval {'use Net::RabbitMQ'};
    plan skip_all => 'Net::RabbitMQ Not present ' if $@;
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
        ReportEngine =>
            { Mode => 'Filesystem', reportFilesystemRoot => $self->{storedir} },
        StorageEngine => { Mode => 'Memory' },
    };
}

sub alldone : Test(teardown) {
}

Test::Class->runtests();
