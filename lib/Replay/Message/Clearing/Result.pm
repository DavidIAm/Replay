package Replay::Message::Clearing::Result;
use Moose;
with qw/Replay::Role::Envelope/;

our $VERSION = '0.04';

has '+name'    => ( default => 'Primera' );
has '+version' => ( default => 1 );
has 'decided'  => (
    is          => 'ro',
    isa         => 'Num',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'message' },
);

1;
