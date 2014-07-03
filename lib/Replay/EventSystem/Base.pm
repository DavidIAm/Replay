package Replay::EventSystem::Base;

# provides a base type to check communication channel implimentations against

use Moose;

# purpose is the channel name, such as 'control', 'origin', or 'derived' but
# may be arbitrary
has purpose => ( is => 'ro', isa => 'Str', required => 1 );

# Config contains information used to connect to the queuing solution
has config => ( is => 'ro', isa => 'HashRef[Item]', required => 1 );

sub emit { die "stub, implement emit" }
sub subscribe { die "stub, implement subscribe" }
sub poll { die "stub, implement poll" }

1;
