package Replay::Message::Reported;

use Moose;
extends('Replay::Message');
with('Replay::Role::IdKey');

our $VERSION = '0.03';

has '+MessageType' => ( default => 'Reported' );

has inReactionToType => ( is => 'ro', isa => 'Str', required => 1, );
has inReactionToUUID => ( is => 'ro', isa => 'Str', required => 1, );

1;

