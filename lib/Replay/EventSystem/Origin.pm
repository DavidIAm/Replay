package Replay::EventSystem;

use Moose;

use EV;
use AnyEvent;

has subscribers => (is => 'ro', isa => 'ArrayRef', default => sub { [] },);
has timeout => (is => 'ro', isa => 'Int');

sub BUILD {
    my ($self) = @_;
    my ($generalHandler, $establisher);
    $self->{stop} = AnyEvent->condvar(cb => sub {exit});
    $generalHandler = sub {
        while (my $message = shift @{ $self->{events} }) {
            $_->($message) foreach (@{ $self->subscribers });
        }
        $establisher->();    # reassert
    };
    $establisher = sub {
        $self->{dog} = AnyEvent->condvar(cb => $generalHandler);
    };
    $establisher->();        # assert
}

sub run {
    my ($self) = @_;
    AnyEvent->timer(after => 1, interval => 1, cb => sub { warn "<3\n"; });
    AE::timer(1, 1, sub { warn "<3-\n"; });
    AnyEvent->timer(
        after => $self->timeout,
        cb    => sub { warn "TRYING TO STOP"; $self->stop }
    ) if $self->timeout;
    EV::loop;
}

sub stop {
    my ($self) = @_;
    warn "STOPPING";
    EV::unloop;
}

sub processingTrigger {
	my $self = shift
    AnyEvent::postpone { $self->{dog}->send(); };
}

sub addEventForProcessing {
	my $self = shift;
    push @{ $self->{events} }, $message;
}

sub emit {
    my ($self, $message) = @_;
    use Data::Dumper;
		$self->addEventforProcessing($message);
		$self->processingTrigger;
}

sub subscribe {
    my ($self, $callback) = @_;
    die 'callback must be code' unless 'CODE' eq ref $callback;
    push @{ $self->subscribers }, $callback;
}

1;
