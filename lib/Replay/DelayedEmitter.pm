package Replay::DelayedEmitter;

use Moose;

has eventSystem  => (is => 'ro', isa => 'Replay::EventSystem', required => 1);
has bundles      => (is => 'rw', isa => 'ArrayRef',            required => 1);
has ruleversions => (is => 'rw', isa => 'ArrayRef',            required => 1);
has messagesToSend => (is => 'rw', isa => 'ArrayRef', default => sub { [] });

sub emit {
    my $self    = shift;
    my $message = shift;
    die unless $message->isa('CargoTel::Message');

    # augment with metadata from storage
    $message->bundles($self->bundles);
    $message->ruleversions($self->ruleversions);
    push @{ $self->messagesToSend }, $message;
    return 1;
}

sub release {
    my $self = shift;
    foreach (@{ $self->messagesToSend }) {
        $self->eventSystem->derived->emit($_);
    }
}

1;
