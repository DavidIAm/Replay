package Replay::Message::Timing;

use Moose;
extends('Replay::Message');

our $VERSION = '0.03';

has '+MessageType' => ( default => 'Timing' );

has 'epoch' => (
    is          => 'ro',
    isa         => 'Int',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'message' },
);
has 'minute' => (
    is          => 'ro',
    isa         => 'Int',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'message' },
);
has 'hour' => (
    is          => 'ro',
    isa         => 'Int',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'message' },
);
has 'date' => (
    is          => 'ro',
    isa         => 'Int',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'message' },
);
has 'month' => (
    is          => 'ro',
    isa         => 'Int',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'message' },
);
has 'year' => (
    is          => 'ro',
    isa         => 'Int',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'message' },
);
has 'weekday' => (
    is          => 'ro',
    isa         => 'Int',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'message' },
);
has 'yearday' => (
    is          => 'ro',
    isa         => 'Int',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'message' },
);
has 'isdst' => (
    is          => 'ro',
    isa         => 'Int',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'message' },
);

1;

