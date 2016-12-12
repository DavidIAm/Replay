package Replay::Message::Unlocked;

use Moose;
extends('Replay::Message');
with('Replay::Role::IdKey');

our $VERSION = '0.03';

has '+MessageType' => ( default => 'Unlocked' );
1;

