package Replay::Message::Reverted;

use Moose;
use Moose::Util::TypeConstraints;
use Replay::Message::IdKey;

extends qw/Replay::Message::IdKey Replay::Message/;

has messageType => (
	is => 'ro',
	isa => 'Str',
	default => 'Reverted',
);

1;

