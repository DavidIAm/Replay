package Replay::Message::Base;

use Moose;
use MooseX::Storage;

with Storage ( format => 'JSON' );

has message => ( is => 'ro', isa => 'Replay::Message', required => 1 );
has messageType => ( is => 'ro', isa => 'Str', required => 1 );
has effectiveTime => ( is => 'ro', isa => 'Str', required => 1, builder => '_now' );



