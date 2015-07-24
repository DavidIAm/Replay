package Test::Replay::ReportMongo;

use lib 't/lib';

use base qw/Replay::Test/;

sub t_environment_reset : Test(startup) {
    my $self   = shift;
    my $replay = $self->{replay};
    $replay->reportEngine->engine->db->drop;
}

sub a_replay_config : Test(startup) {
    my $self = shift;
    $self->{config} = {
        Defaults=>{
          ReportEngine=> 'Mongo'},
        stage         => 'testscript-08-' . $ENV{USER},
        EventSystem   => { Mode => 'Null', },
        StorageEngine => { Mode => 'Memory', },
        ReportEngines => {
            Mongo =>{MongoUser => 'replayuser',
            MongoPass => 'replaypass'},
        },
        timeout => 10,
    };
}

sub alldone : Test(teardown) {
}

Test::Class->runtests();


 Defaults=>{
          ReportEngine=>'Filesystem'},
        stage   => 'testscript-07-' . $ENV{USER},
 Defaults=>{
          ReportEngine=>'Filesystem'},
        stage   => 'testscript-07-' . $ENV{USER},
        EventSystem   => { Mode => 'Null', },
        StorageEngine => { Mode => 'Memory', },
        ReportEngines =>
            {Filesystem =>{Root =>$self->{storedir},Access=>'public',} },
        timeout => 10,

