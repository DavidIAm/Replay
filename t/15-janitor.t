package Test::Replay::Janitor;

do {

    package Replay::EventSystem;
    package MockEventSystem;
    use base ('Replay::EventSystem');

    sub new {
        my ( $class, %args ) = @_;
        return bless {%args}, $class;
    }

    sub register_cleanup_timer {
        my ( $self, %args ) = @_;
        $self->{rct}++;
        $self->{rctargs} = \%args;
    }
};
do {

    package Replay::StorageEngine;
    package MockStorageEngine;
    use base ('Replay::StorageEngine');

    sub new {
        my ( $class, %args ) = @_;
        return bless {%args}, $class;
    }

    sub revert_all_expired_locks {
        my ( $self, %args ) = @_;
        $self->{rael}++;
        $self->{raelargs} = \%args;
    }
};

use lib 't/lib';

use base qw(Test::Class);

use Test::Most;
use Test::MockModule;
use File::Path;
use Replay::Janitor;

sub t_environment_reset : Test(setup) {
    my $self = shift;
    $self->{eventSystem} = MockEventSystem->new( );
    $self->{storageEngine} = MockStorageEngine->new( );
}

sub a_specific : Tests {
    my $self    = shift;
    my $rct     = 0;
    my $rael    = 0;
    my %args    = ();
    my $janitor = Replay::Janitor->new(
        config        => { Janitor => { interval => 60 } },
        storageEngine => $self->{storageEngine},
        eventSystem   => $self->{eventSystem},
    );
    ok $self->{eventSystem}{rct}, "register_cleanup_timer called";
    is $self->{eventSystem}{rctargs}{interval} => 60,
        "interval set to 60 seconds";
    ok eval { $self->{eventSystem}{rctargs}{callback}->(); 1; },
        "can call the callback";
    ok $self->{storageEngine}{rael}, "revert_all_expired_locks callable";
}

sub a_default : Tests {
    my $self    = shift;
    my $rct     = 0;
    my $rael    = 0;
    my %args    = ();
    my $janitor = Replay::Janitor->new(
        config        => {},
        storageEngine => $self->{storageEngine},
        eventSystem   => $self->{eventSystem},
    );
    ok $self->{eventSystem}{rctargs}{interval} == 90,
        "interval set to 90 seconds";
}

sub alldone : Test(teardown) {
}

Test::Class->runtests();

1;
