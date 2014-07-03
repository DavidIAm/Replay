package Replay::Message::Fetched;

use Moose;
use Moose::Util::TypeConstraints;
use Replay::Message::IdKey;

extends qw/Replay::Message::IdKey/;

has messageType => (
	is => 'ro',
	isa => 'Str',
	default => 'Fetched',
);

1;
