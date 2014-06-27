package Replay::Message::RulesReady;

use Moose;
use Replay::Message::IdKey;

extends 'Replay::Message';

has messageType => (
	is => 'ro',
	isa => 'Str',
	default => 'RulesReady',
);

1;
