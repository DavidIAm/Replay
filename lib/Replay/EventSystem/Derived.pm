package Replay::EventSystem::Derived;

use Replay::EventSystem::Queue;
extends 'Replay::EventSystem::Queue';

use Moose;

sub purpose {
    'derived';
}

1;
