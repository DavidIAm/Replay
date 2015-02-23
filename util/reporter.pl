#!/usr/bin/perl

# usage: mapper.pl CONFIGFILE
# where CONFIGFILE is the path to a Config::Any data structure appropriate

use Replay;
use Config::Any;

my $replay = Replay->new(Config::Any->parse $ARGV[0]);

$replay->reporter;

$replay->eventSystem->run;

