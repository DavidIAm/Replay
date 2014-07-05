package Replay::RuleSource;

=pod

=head1 Replay::RuleSource

Provider of a set of objects of type Replay::BusinesRule

The purpose of this abstraction is to allow the dramatic scaling of these rules   Not everything needs to be in memory at the same time.

Current iteration takes an array of Business Rules.  Maybe its tied?

=head1 API

=over 4

=item next 

Deliver the next business rule.  Undef means the end of the list, which resets the pointer to the first.

=item first 

Reset the current rule pointer and deliver the first business rule

=item byIdKey 

The IDKey hash/object is used to identify particular rules.  Given a particular
IdKey state, this routine should return all of the rules that match it.  This is
expected to be a list of one or zero.

=back 4

=cut

use Moose;
use Replay::Message::RulesReady;

has rules => (is => 'ro', isa => 'ArrayRef[Replay::BusinessRule]',);

has index => (is => 'rw', default => 0,);
has eventSystem => (is => 'ro', isa => 'Replay::EventSystem', required => 1);

sub next {
    my ($self) = @_;
    my $i = $self->index;
    $self->index($self->index + 1);
    do { $self->index(0) and return } if $#{ $self->rules } < $i;
    return $self->rules->[$i];
}

sub first {
    my ($self) = @_;
    $self->index(0);
    return $self->rules->[ $self->index ];
}

sub byIdKey {
    my ($self, $idkey) = @_;
    return (grep { $_->name eq $idkey->{name} && $_->version eq $idkey->{version} }
            @{ $self->rules })[0];
}

1;
