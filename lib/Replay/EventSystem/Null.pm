package Replay::EventSystem::Null;

# An event system channel for testing - it doesn't actually
# share a queue with anything else, just runs things in a simple array in
# memory.  Good enough for testing functionality without a dependency on
# a queing solution like RabbitMQ, ZeroMQ, AWS SNS/SQS, or anything like that

use Moose;

use Replay::EventSystem::Base;
extends 'Replay::EventSystem::Base';

has subscribers => (is => 'ro', isa => 'ArrayRef', default => sub { [] },);

sub poll {
    my $self = shift;
    my $c    = 0;
    while (my $message = shift @{ $self->{events} }) {
        $c++;
        $_->($message) foreach (@{ $self->subscribers });
    }
    return $c;
}

sub emit {
    my ($self, $message) = @_;
    push @{ $self->{events} }, $message;
}

sub subscribe {
    my ($self, $callback) = @_;
    die 'callback must be code' unless 'CODE' eq ref $callback;
    push @{ $self->subscribers }, $callback;
}

1;
