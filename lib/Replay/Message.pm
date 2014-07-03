package Replay::Message;

use Moose;
use MooseX::Storage;
use MooseX::MetaDescription::Meta::Trait;
use Time::HiRes qw/gettimeofday/;
use Data::UUID;

extends 'Replay::Message::Base';
with Storage(format => 'JSON');

=pod 

Documentation
 
=cut

has messageType => (
    is        => 'ro',
    isa       => 'Str',
    required  => 1,
    init_arg  => 'messageType',
		traits      => ['MooseX::MetaDescription::Meta::Trait'],
		description => { layer => 'envelope' },
);
has program => (
    is        => 'ro',
    isa       => 'Str',
    required  => 0,
    init_arg  => 'program',
    predicate => 'has_program',
		traits      => ['MooseX::MetaDescription::Meta::Trait'],
		description => { layer => 'envelope' },
);
has function => (
    is        => 'ro',
    isa       => 'Str',
    required  => 0,
    init_arg  => 'function',
    predicate => 'has_function',
		traits      => ['MooseX::MetaDescription::Meta::Trait'],
		description => { layer => 'envelope' },
);
has line => (
    is        => 'ro',
    isa       => 'Str',
    required  => 0,
    init_arg  => 'line',
    predicate => 'has_line',
		traits      => ['MooseX::MetaDescription::Meta::Trait'],
		description => { layer => 'envelope' },
);
has effectiveTime => (
    is        => 'ro',
    isa       => 'Str',
    required  => 0,
    init_arg  => 'effectiveTime',
    predicate => 'has_effective_time',
		traits      => ['MooseX::MetaDescription::Meta::Trait'],
		description => { layer => 'envelope' },
);
has createdTime => (
    is        => 'ro',
    isa       => 'Str',
    required  => 0,
    init_arg  => 'createdTime',
    predicate => 'has_created_time',
		traits      => ['MooseX::MetaDescription::Meta::Trait'],
		description => { layer => 'envelope' },
    builder   => '_now'
);
has receivedTime => (
    is        => 'ro',
    isa       => 'Str',
    required  => 0,
    init_arg  => 'receivedTime',
    predicate => 'has_recieved_time',
		traits      => ['MooseX::MetaDescription::Meta::Trait'],
		description => { layer => 'envelope' },
    builder   => '_now'
);

has uuid => (
    is        => 'ro',
    isa       => 'Str',
    required  => 0,
    init_arg  => 'receivedTime',
    builder   => '_build_uuid',
		traits      => ['MooseX::MetaDescription::Meta::Trait'],
		description => { layer => 'envelope' },
);

sub marshall {
    my $self     = shift;
    my $envelope = Replay::Message::Envelope->new(
        messsage    => $self,
        messageType => $self->messageType,
				uuid => $self->uuid,
        ($self->has_program ? (program => $self->program) : ()),
        ($self->has_function ? (function => $self->function) : ()),
        ($self->has_line     ? (line     => $self->line)     : ()),
        (   $self->has_effective_time ? (effective_time => $self->effectiveTime) : ()
        ),
        ($self->has_created_time  ? (created_time  => $self->createdTime)  : ()),
        ($self->has_received_time ? (received_time => $self->receivedTime) : ()),
    );
}

sub _now {
    my $self = shift;
    return +gettimeofday;
}

sub _build_uuid {
	my $self = shift;
	my $ug = Data::UUID->new;
	return $ug->to_string($ug->create());
}

1;
