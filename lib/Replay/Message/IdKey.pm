package Replay::Message::IdKey;

use Moose;
extends qw/Replay::Message/;

has name => (is => 'ro', isa => 'Str',);

has version => (is => 'ro', isa => 'Str',);

has window => (is => 'ro', isa => 'Str',);

has key => (is => 'ro', isa => 'Str',);

1;
