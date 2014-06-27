package Replay::Message::Reducing;

use Moose;
use Replay::Message::IdKey;

extends qw/Replay::Message::IdKey Replay::Message/;

has messageType => (
	is => 'ro',
	isa => 'Str',
	default => 'Reducing',
);

1;

