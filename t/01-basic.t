package Test::Replay::Null::Memory::Filesystem;

use lib 't/lib';
use File::Temp qw/tempdir/;

use base qw/Replay::Test Test::Class/;

use Test::Most;


sub t_environment_reset : Test(startup) {
    my $self   = shift;
    my $replay = $self->{replay};
}

sub a_replay_config : Test(startup) {
    my $self = shift;
    $self->{config}   = {
        stage         => 'testscript-01-' . $ENV{USER},
        EventSystem   => { Mode => 'Null' },
        StorageEngine => { Mode => 'Memory' },
        WORM          => { Directory => tempdir },
        timeout       => 50,
        Defaults      => { ReportEngine => 'Filesystemtest' },
        ReportEngines => [{ Mode =>'Filesystem',
                            Root => tempdir,
                            Name => 'Filesystemtest',
                            Access => 'public' } ]

    };
}

sub alldone : Test(teardown) {
    File::Temp::cleanup;
}

Test::Class->runtests();

1;
