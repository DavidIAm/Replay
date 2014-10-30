package Replay::Message::Clearing::Error;
use Moose;
with qw/Replay::Envelope/;
has '+name'    => (default => 'Primera');
has '+version' => (default => 1);
has 'decided'  => (
    is          => 'ro',
    isa         => 'Num',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'message' },
);

1;
