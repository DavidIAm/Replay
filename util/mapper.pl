#!/usr/bin/perl

# usage: mapper.pl CONFIGFILE
# where CONFIGFILE is the path to a Config::Any data structure appropriate

use Replay;
use File::Slurp;
use YAML;
use Data::Dumper;
my $replay = Replay->new(config => YAML::Load(join '', read_file($ARGV[0])));

$replay->mapper;

$replay->eventSystem->run;

