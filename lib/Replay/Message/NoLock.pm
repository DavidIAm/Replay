package Replay::Message::NoLock;

use Moose;
extends('Replay::Message');
with('Replay::Role::IdKey');

our $VERSION = '0.03';

has '+MessageType' => ( default => 'NoLock' );
1;

