package Replay::Message::Reduced;

use Moose;
extends('Replay::Message');
with('Replay::Role::IdKey');

our $VERSION = '0.03';

has '+MessageType' => ( default => 'Reduced' );

1;

