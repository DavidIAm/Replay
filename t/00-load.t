#!perl -T
use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;

plan tests => 1;

BEGIN {
    use_ok('Replay') || print "Bail out!\n";
}

my $replay = Replay->new(
    rules  => [],
    config => { QueueClass => 'Replay::EventSystem::Null' }
);

diag("Testing Replay $Replay::VERSION, Perl $], $^X");
