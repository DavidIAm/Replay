package Test::Replay::BASICTEST;

use lib 't/lib';

use Replay::Test;
use Test::Class;

use base qw/Replay::Test Test::Class/;

use Test::Most qw/bail/;

sub t_environment_reset : Test(startup => 1) {
    warn "REPLAY RESET" if $ENV{DEBUG_REPLAY_TEST};
    my $self   = shift;
    `rm -rf $self->{storedir}`;
    ok !-d $self->{storedir};
    $self->{replay}->storageEngine->engine->reset;
}

sub a_replay_config : Test(startup => 1) {
    warn "REPLAY CONFIG" if $ENV{DEBUG_REPLAY_TEST};
    my $self = shift;
    $self->{storedir} = '/tmp/testscript-01-' . $ENV{USER};
    $self->{config}   = {
        timeout       => 10,
        timeoutcb       => sub { ok 0, "ACK TIMED OUT" },
        stage         => 'testscript-01-' . $ENV{USER},
        EventSystem   => { Mode => 'Null' },
        StorageEngine => { Mode => 'Memory' },
        Defaults      => { ReportEngine => 'Memory' },
        ReportEngines => { Memory => { Mode => 'Memory' } },
    };
    ok $self->{config}, "Configure";
}

sub alldone : Test(teardown) {
}

__PACKAGE__->runtests();

1;
