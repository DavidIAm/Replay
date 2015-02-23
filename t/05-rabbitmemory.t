package Test::Replay::RabbitMemory;

use lib 't/lib';

use base qw/Replay::Test Test::Class/;
use JSON;
use File::Slurp;
use Test::Most qw/bail/;

=pod
sub t_environment_reset : Test(startup) {
    use Replay;
    Replay::ReportEngine->new(
        config => {
            ReportEngine => {
                Mode      => 'Mongo',
                User => 'replayuser',
                Pass => 'replaypass',
            },
        },
        rule => []
        )
        ->engine->collection(Replay::IdKey->new(name => 'TESTRULE', version => 1))
        ->remove();
}
=cut

sub t_environment_reset : Test(startup => 1) {
    my $self = shift;
    `rm -rf $self->{storedir}`;
    ok !-d $self->{storedir};
}

sub a_replay_config : Test(startup) {
    my $self = shift;
    $self->{storedir} = '/tmp/testscript-05-' . $ENV{USER};
    $self->{config}   = {
        stage       => 'tests',
        EventSystem => {
            Mode     => 'RabbitMQ',
            RabbitMQ => {
                host    => 'localhost',
                options => {
                    port        => '5672',
                    user        => 'replay',
                    password    => 'replaypass',
                    vhost       => '/replay',
                    timeout     => 30,
                    tls         => 1,
                    heartbeat   => 1,
                    channel_max => 0,
                    frame_max   => 131072
                },
            },
        },
        StorageEngine => { Mode => 'Memory' },
        Defaults      => { ReportEngine => 'Memory' },
        ReportEngines => { Memory => { Mode => 'Memory' } },
    };
}

sub alldone : Test(teardown) {
my ($self) = @_;
    $self->{replay}->eventSystem->origin->purge();
    $self->{replay}->eventSystem->derived->purge();
    $self->{replay}->eventSystem->control->purge();
}

__PACKAGE__->runtests();
