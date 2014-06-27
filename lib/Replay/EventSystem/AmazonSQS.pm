package Replay::EventSystem::AmazonSQS;

use Moose;

use Amazon::SQS::Simple;

has amazonQueueService => (
);
has amazonQueue => (
	is => 'ro',
	isa => 'Amazon::SQS::Simple::Queue',
);

around BUILD => sub {
	# when we get a message from the queue, add it to the events list
	$self->addEventForProcessing($materializedmessage);
	$self->processingTrigger;
	# when we get an emit, send the message to the queue
};

override emit => sub {
    my ($self, $message) = @_;
    $self->{queue}
};



1;
