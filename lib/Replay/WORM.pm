package Replay::WORM;

use Moose;
use POSIX qw/strftime/;
use File::Spec qw//;

has eventSystem => (is => 'ro', required => 1,);
has directory   => (is => 'ro', required => 0, default => '/var/log/replay');
has filehandles => (is => 'ro', isa      => 'HashRef', default => sub { {} });

# dummy implimentation - Log them to a file
sub BUILD {
    my $self = shift;
    mkdir $self->directory unless -d $self->directory;
    $self->eventSystem->origin->subscribe(
        sub {
            $self->log(@_);
            $self->eventSystem->derived->emit(@_);
        }
    );
}

sub log {
    my $self    = shift;
    my $message = shift;
    $self->filehandle->print("$message");
}

sub path {
    my $self = shift;
    File::Spec->catfile($self->directory, $self->bundle);
}

sub filehandle {
    my $self = shift;
    return $self->filehandles->{ $self->bundle }
        if -f $self->filehandles->{ $self->bundle };
    open $self->filehandles->{ $self->bundle }, '>>', $self->path
        or confess "Unable to open " . $self->path . " for append";
    return $self->filehandles->{ $self->bundle };
}

sub bundle {
    my $self = shift;
    return strftime '%Y-%m-%d-%H', localtime time;
}

1;
