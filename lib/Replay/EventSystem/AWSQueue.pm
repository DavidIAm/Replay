package Replay::EventSystem::AWSQueue;

=pod

=head1 Public API

constructor properties
        purpose => $purpose,
        config  => $self->config,

This object instance will be distinct for $purpose, but may be singleton per purpose.

config is a Hashref object which will have available appropriate bits in its config for this configuration.

=head2 AWS Specific notes

this implementation uses config values

stage: test
Replay:
  awsIdentity: 
    access: 'AKIAJUZLBY2RIDB6LSJA'
    secret: '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'
  snsService: 'https://sns.us-east-1.amazonaws.com'
  sqsService: 'https://sqs.us-east-1.amazonaws.com'


This account is expected to have the permissions to create topics and queues.

It will create SNS topic for each indicated purpose named <stage>-replay-<purpose>

It will create SQS queues for each instance, named <stage>-replay-<purpose>-<uuid>

=over 4 

=item emit($message)

Send a message to the channel that this class encapsulates.
sends as string if string, frozen with ->freeze if method available, or json if other ref

Channel does not need to be initialized if there are never any emits

=item subscribe(callback)

Add to a list of callbacks that will be called with the messages recieved.

Queue does not need to be initialized if there are no subscribers.

=item poll()

Do what is necessary to pull down an available message from a queue subscribed to this channel

Only do this if there are subscribers listening to the events.

Make sure you call each of the subscriber callbacks with the message

=back 4

=cut

use Moose;

use Replay::EventSystem::Base;
extends 'Replay::EventSystem::Base';

use Amazon::SNS;
use Try::Tiny;
use Amazon::SQS::Simple;
use Data::UUID;
use JSON;
use Scalar::Util qw/blessed/;
use Carp qw/confess/;

has purpose => (is => 'ro', isa => 'Str', required => 1,);
has subscribers => (is => 'ro', isa => 'ArrayRef', default => sub { [] },);
has sns =>
    (is => 'ro', isa => 'Amazon::SNS', builder => '_build_sns', lazy => 1,);
has sqs => (
    is      => 'ro',
    isa     => 'Amazon::SQS::Simple',
    builder => '_build_sqs',
    lazy    => 1,
);

has config => (is => 'ro', isa => 'HashRef[Item]', required => 1);

has queue => (
    is        => 'ro',
    isa       => 'Amazon::SQS::Simple::Queue',
    builder   => '_build_queue',
    predicate => 'has_queue',
    lazy      => 1,
);

has topic => (
    is      => 'ro',
    isa     => 'Amazon::SNS::Topic',
    builder => '_build_topic',
    lazy    => 1,
);

has topicarn => (is => 'ro', isa => 'Str', predicate => 'has_topicarn');
has topicName =>
    (is => 'ro', isa => 'Str', builder => '_build_topicName', lazy => 1,);
has queuearn =>
    (is => 'ro', isa => 'Str', builder => '_build_queuearn', lazy => 1);
has queueName =>
    (is => 'ro', isa => 'Str', builder => '_build_queueName', lazy => 1);

sub emit {
    my ($self, $message) = @_;
    $message = $message->stringify
        if blessed $message && $message->can('stringify');
    $message = $message->freeze if blessed $message && $message->can('freeze');
    try {
        $message = to_json($message) if ref $message;
    }
    catch {
        use Data::Dumper;
        die "WE WERE TRYING TO EMIT A "
            . ref($message)
            . " BUT GOT EXCEPTIOIN $_ - NO STRINGIFY OR FREEZE??"
            . Dumper $message;
    };

    return $self->topic->Publish($message, 'control');
}

sub poll {
    my ($self) = @_;
    my $handled = 0;

    # only check the channels if we have been shown an interest in
    return $handled unless scalar(@{ $self->subscribers });
    foreach my $message ($self->receive()) {
      $handled++;
        foreach my $subscriber (@{ $self->subscribers }) {
            try {
                $subscriber->($message);
            }
            catch {
                warn "There was an exception while processing message through subscriber "
                    . $_;
            }
        }
    }
    return $handled;
}

sub subscribe {
    my ($self, $callback) = @_;
    die 'callback must be code' unless 'CODE' eq ref $callback;
    push @{ $self->subscribers }, $callback;
}

sub acknowledge {
  my ($self, @messages) = @_;
    $self->queue->DeleteMessageBatch([@messages]);;
}

sub receive {
    my ($self)   = @_;
    my @messages = $self->queue->ReceiveMessageBatch;
    return unless scalar @messages;
    $self->acknowledge(@messages);
    map {    #}{
        try {
            my $messageBody = from_json $_->MessageBody;
            try {
                my $innermessage = from_json $messageBody->{Message};
                $innermessage->{__CLASS__}
                    ? $innermessage->{__CLASS__}->thaw($messageBody->{Message})
                    : $innermessage;
            }
            catch {
                $messageBody->{Message};
            }
        }
        catch {
            $_->MessageBody;
        }
    } @messages;
}

sub _build_sqs {
    my ($self) = @_;
    my $config = $self->config->{Replay};
    die "No sqs service?" unless $config->{sqsService};
    my $sqs = Amazon::SQS::Simple->new(
        $config->{awsIdentity}{access},
        $config->{awsIdentity}{secret},
        Endpoint => $config->{sqsService}
    );
    return $sqs;
}

sub _build_sns {
    my ($self) = @_;
    my $config = $self->config->{Replay};
    my $sns    = Amazon::SNS->new(
        {   key    => $config->{awsIdentity}{access},
            secret => $config->{awsIdentity}{secret}
        }
    );
    $sns->service($config->{snsService});
    return $sns;
}

sub _build_queue {
    my ($self) = @_;
		warn "BUILDING QUEUE ".$self->queueName;
    my $queue = $self->sqs->CreateQueue($self->queueName);
    $queue->SetAttribute(
        'Policy',
        to_json(
            {   "Version"   => "2012-10-17",
                "Statement" => [
                    {   "Sid"       => "PolicyForQueue" . $self->queueName,
                        "Effect"    => "Allow",
                        "Principal" => { "AWS" => "*" },
                        "Action"    => "sqs:SendMessage",
                        "Resource"  => $self->queuearn,
                        "Condition" => { "ArnEquals" => { "aws:SourceArn" => $self->topic->arn } }
                    }
                ]
            }
        )
    );
    $self->{subscriptionARN} = $self->sns->dispatch(
        {   Action   => 'Subscribe',
            Endpoint => $self->queuearn,
            Protocol => 'sqs',
            TopicArn => $self->topic->arn,
        }
    )->{'SubscribeResult'}{'SubscriptionArn'};
    return $queue;
}

sub DEMOLISH {
    my ($self) = @_;
    $self->queue->Delete if $self->has_queue && $self->queue;
    $self->sns->dispatch(
        { Action => 'Unsubscribe', SubscriptionArn => $self->{subscriptionARN} })
        if $self->{subscriptionARN};
}

sub _build_topicName {
    my ($self) = @_;
    confess "No purpose" unless $self->purpose;
    return join '_', $self->config->{stage}, 'replay', $self->purpose;
}

sub _build_topic {
    my ($self) = @_;
    my $topic;
		warn "BUILDING TOPIC ".$self->topicName;
    if ($self->has_topicarn) {
        $topic = $self->sns->GetTopic($self->topicarn);
    }
    else {
        $topic = $self->sns->CreateTopic($self->topicName);
    }
    return $topic;
}

sub _build_queueName {
    my $self = shift;
    my $ug   = Data::UUID->new;
    return join '_', $self->config->{stage}, 'replay', $self->purpose,
        $ug->to_string($ug->create);
}

# this derives the arn from the topic name.
sub _build_queuearn {
    my $self = shift;
    my ($type, $domain, $service, $region, $id, $name) = split ':',
        $self->topic->arn;
    my $qarn = join ':', $type, $domain, 'sqs', $region, $id, $self->queueName;
}

1;
