package Replay::Message::Clock;

use Moose;
use Replay::Message;
extends 'Replay::Message';

has epoch => ( is => 'ro', isa => 'Int', required => 1 );
has minute => ( is => 'ro', isa => 'Int', required => 1 );
has hour => ( is => 'ro', isa => 'Int', required => 1 );
has date => ( is => 'ro', isa => 'Int', required => 1 );
has month => ( is => 'ro', isa => 'Int', required => 1 );
has year => ( is => 'ro', isa => 'Int', required => 1 );
has weekday => ( is => 'ro', isa => 'Int', required => 1 );
has yearday => ( is => 'ro', isa => 'Int', required => 1 );
has isdst => ( is => 'ro', isa => 'Int', required => 1 );

