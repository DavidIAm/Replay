package Test::Replay::ReportFilesystem;

use lib 't/lib';

use base qw/Replay::Test/;
use Test::Most;
use File::Temp qw/tempdir/;


sub a_replay_config : Test(startup) {
    my $self = shift;
    $self->{config}   = {
         stage   => 'testscript-07-' . $ENV{USER},
        EventSystem   => { Mode => 'Null', },
        StorageEngine => { Mode => 'Memory', },
         Defaults      => { ReportEngine => 'Filesystemtest' },
        ReportEngines => [{ Mode =>'Filesystem',
                            Root => tempdir,
                            Name => 'Filesystemtest',
                            Access => 'public' } ],
       timeout => 10,
    };
}

sub alldone : Test(teardown) {
}

Test::Class->runtests();
