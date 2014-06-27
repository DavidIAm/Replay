package Replay::Message::WindowAll;

use Moose;
use Moose::Util::TypeConstraints;
use Replay::Message::IdKey;

extends qw/Replay::Message::IdKey Replay::Message/;

has messageType => (
	is => 'ro',
	isa => 'Str',
	default => 'WindowAll',
);

1;

