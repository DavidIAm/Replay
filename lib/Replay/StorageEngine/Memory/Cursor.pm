package Replay::StorageEngine::Memory::Cursor;

use Data::Dumper;

sub new {
    my ( $class, @list ) = @_;
    my $self = bless {}, __PACKAGE__;
    $self->{list}  = [@list];
    $self->{index} = 0;
    return $self;
}

sub all {
    my ($self) = @_;
    return @{ $self->{list} };
}

sub first {
    my ($self) = @_;
    $self->{index} = 0;
    return $self->next;
}

sub next {
    my ($self) = @_;
    $self->{list}->[ $self->{index}++ ];
}

sub batch {
    my ($self) = @_;
    my $list = $self->{list};
    $self->{list} = [];
    @{$list};
}

sub has_next {
    my ($self) = @_;
   return $self->{index} <= $#{ $self->{list} };
}

1;
