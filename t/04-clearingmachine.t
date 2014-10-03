#!/usr/bin/perl

use lib 'Replay/lib/';

package TESTRULE;

use Moose;
extends qw/Replay::Rules::ClearingBase/;
use Replay::Types;
use List::Util qw//;
with 'Replay::Role::BusinessRule' => {  -version => 0.02 };
with 'Replay::Role::ClearingMachine' => {  -version => 0.02 };


sub initial_match {
    my ($self, $message) = @_;
    return $message->{MessageType} eq 'interesting';
}

sub window {
    my ($self, $message) = @_;
    return 'alltime';
}

sub key_value_set {
    my ($self, $message) = @_;
    my @keyvalues = ();
    foreach my $key (keys %{$message->{Message}}) {
        next unless 'ARRAY' eq ref $message->{Message}->{$key};
        foreach (@{ $message->{Message}->{$key} }) {
            push @keyvalues, $key, $_;
        }
    }
    return @keyvalues;
}

sub compare {
    my ($self, $aa, $bb) = @_;
    return ($aa || 0) <=> ($bb || 0);
}

sub reduce {
    my ($self, $emitter, @state) = @_;
    my $response = List::Util::reduce { $a + $b } @state;
}

