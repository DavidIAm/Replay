package Replay::Types::Messages;
use Moose::Role;
use Moose::Util::TypeConstraints;
#use namespace::autoclean;
use Replay::Message::Clock;
use Replay::Message::IdKey;

class_type 'Clock', { class => 'Replay::Message::Clock' };
coerce 'Clock',
      from 'HashRef',
      via { Replay::Message::Clock->new(%{ $_ }) };

class_type 'IdKey', { class => 'Replay::Message::IdKey' };
coerce 'IdKey',
      from 'HashRef',
      via { Replay::Message::IdKey->new(%{ $_ }) };

1;

