package Test::Replay::AWSQueue::Mongo::Filesystem;

use lib 't/lib';

use base qw/Replay::Test Test::Class/;

use Test::Most;
use Test::Mojo;

sub t_environment_reset : Test(startup => 1) {
    my $self   = shift;
    my $replay = $self->{replay};
    `rm -rf $self->{storedir}`;
    ok !-d $self->{storedir};
}

sub z_replay_initialize : Test(startup) {
  my $self = shift;
  
}
sub a_replay_config : Test(startup) {
    my $self = shift;
    $self->{storedir} = '/tmp/testscript-09-' . $ENV{USER};
    $self->{config}   = {
        stage         => 'testscript-09-' . $ENV{USER},
        EventSystem   => { Mode => 'Null' },
        StorageEngine => { Mode => 'Memory' },
        timeout       => 50,
        Defaults      => { ReportEngine => 'Filesystem' },
        ReportEngines => [
            {
                Name => 'Filesystem',
                Mode => 'Filesystem',
                Root => $self->{storedir},
                REST => {
                    Listen   => 'http://[::]:3009',
                    Backlog  => 50000,
                    Clients  => 1000,
                    Timeout  => 15,
                    Requests => 25,
                    Proxy    => 1,
                }
            }
        ]
    };
}

sub alldone : Test(teardown) {
}

Test::Class->runtests();

1;

