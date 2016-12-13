package Replay::Message::Fetched;

use Moose;
extends('Replay::Message');
with('Replay::Role::IdKey');

our $VERSION = '0.02';

has '+MessageType' => ( default => 'Fetched' );

1;

