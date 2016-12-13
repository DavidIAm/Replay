package Replay::Message::NewCanonical;

use Moose;
extends('Replay::Message');
with('Replay::Role::IdKey');

our $VERSION = '0.02';

has '+MessageType' => ( default => 'NewCanonical' );

1;

