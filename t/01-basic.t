package Test::Replay::AWSQueue::Mongo::Filesystem;

use lib 't/lib';

use base qw/Replay::Test Test::Class/;

use Test::Most qw/bail/;

sub t_environment_reset : Test(startup => 1) {
    my $self   = shift;
    my $replay = $self->{replay};
    `rm -rf $self->{storedir}`;
    ok !-d $self->{storedir};
}

sub a_replay_config : Test(startup) {
    my $self = shift;
    $self->{storedir} = '/tmp/testscript-01-' . $ENV{USER};
    $self->{config}   = {
        timeout       => 10,
        stage         => 'testscript-01-' . $ENV{USER},
        EventSystem   => { Mode => 'Null' },
        StorageEngine => { Mode => 'Memory' },
        ReportEngine  => { Mode => 'Memory' }
    };
}

sub alldone : Test(teardown) {
}

Test::Class->runtests();

1;
