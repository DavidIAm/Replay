package Replay::Message::Locked;

use Moose;
extends('Replay::Message');
with('Replay::Role::IdKey');

our $VERSION = '0.03';

has '+MessageType' => ( default => 'Locked' );

1;

