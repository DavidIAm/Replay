package Replay::Message::NewCanonical;

use Moose;
use Replay::Message::IdKey;

extends qw/Replay::Message::IdKey Replay::Message/;

has messageType => (
	is => 'ro',
	isa => 'Str',
	default => 'NewCanonical',
);

1;
