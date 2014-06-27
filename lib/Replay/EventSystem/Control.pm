package Replay::EventSystem::Control;

use Replay::EventSystem::Queue;
extends 'Replay::EventSystem::Queue';

use Moose;

sub purpose {
    'control';
}

1;
