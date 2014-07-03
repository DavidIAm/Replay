package Replay::Message::Base;

use Moose;
use MooseX::Storage;

with Storage ( format => 'JSON' );

