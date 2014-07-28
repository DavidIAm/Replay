package Replay::EventSystem::AWSQueue;

use Moose;

our $VERSION = '0.01';

use Replay::EventSystem::Base;
with 'Replay::EventSystem::Base';

use Replay::Message;
#use Replay::Message::Clock;

use Perl::Version;
use Amazon::SNS;
use Try::Tiny;
use Amazon::SQS::Simple;
use Data::UUID;
use JSON;
use Scalar::Util qw/blessed/;
use Carp qw/confess/;

has purpose     => (is => 'ro', isa => 'Str',      required => 1,);
has subscribers => (is => 'ro', isa => 'ArrayRef', default  => sub { [] },);
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
warn "TRYING TO EMIT $message";
    $message = $message->stringify
        if blessed $message && $message->can('stringify');
    $message = $message->freeze if blessed $message && $message->can('freeze');
    try {
        $message = to_json($message) if ref $message;
    }
    catch {
        die "WE WERE TRYING TO EMIT A "
            . ref($message)
            . " BUT GOT EXCEPTIOIN $_ - NO STRINGIFY OR FREEZE??"
            . to_json [$message];
    };

    return $self->topic->Publish($message, 'control');
}

sub poll {
    my ($self) = @_;
    my $handled = 0;

    # only check the channels if we have been shown an interest in
    return $handled unless scalar(@{ $self->subscribers });
    foreach my $message ($self->_receive()) {
        $handled++;
        foreach my $subscriber (@{ $self->subscribers }) {
            try {
                $subscriber->($message);
            }
            catch {
                warn "There was an exception while processing message through subscriber "
                    . $_;
            };
        }
    }
    return $handled;
}

sub subscribe {
    my ($self, $callback) = @_;
    die 'callback must be code' unless 'CODE' eq ref $callback;
    push @{ $self->subscribers }, $callback;
}

sub _acknowledge {
    my ($self, @messages) = @_;
    $self->queue->DeleteMessageBatch([@messages]);
}

sub _receive {
    my ($self) = @_;
    my @messages = $self->queue->ReceiveMessageBatch;
    return unless scalar @messages;
    $self->_acknowledge(@messages);
    my @payloads;
    foreach (@messages) {
#        try {
            my $messageBody = from_json $_->MessageBody;
#            try {
                my $innermessage = from_json $messageBody->{Message};
#                if ($innermessage->{__CLASS__}) {
#                    my ($class, $c, $version)
#                        = $innermessage->{__CLASS__} =~ /^(.+?)(-(v?[0-9.[:alpha:]-]+))?$/;
#                    unless ($class) {
#                        warn "Didn't parse out class and version from " . $innermessage->{__CLASS__};
#                        push @payloads, $innermessage;
#                    }
#                    else {
#                        eval "require $class";
#                        warn "RESULT OF REQUIRE OF $class is $@\n" if $@;
#                        if ($version) {
#                            my $packver = Perl::Version->new(eval "\$$class\::VERSION");
#                            my $objver  = Perl::Version->new($version);
#                            die "This object is newer than the package we have!!" if ($objver > $packver);
#                        }
#                        $class->thaw($messageBody->{Message}) || $innermessage;
#                    }
#                }
#                else {
                    push @payloads, $innermessage;
#                }
#            }
#            catch {
#                warn "GOT AN ERROR IN THAWER? $_\n";
#                push @payloads, $messageBody->{Message};
#            }
#        }
#        catch {
#					warn "GOT ERROR IN FROM JSON ON BODY?  $_\n";
#            push @payloads, $_->MessageBody;
#        }
    }
		return @payloads;
}

sub _build_sqs {
    my ($self) = @_;
    my $config = $self->config;
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
    my $config = $self->config;
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
    warn "BUILDING QUEUE " . $self->queueName;
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
    $self->queue->Delete if $self->has_queue && $self->queue && $self->mode eq 'fanout';
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
    warn "BUILDING TOPIC " . $self->topicName;
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
        ($self->mode eq 'fanout' ? $ug->to_string($ug->create) : ());
}

# this derives the arn from the topic name.
sub _build_queuearn {
    my $self = shift;
    my ($type, $domain, $service, $region, $id, $name) = split ':',
        $self->topic->arn;
    my $qarn = join ':', $type, $domain, 'sqs', $region, $id, $self->queueName;
}

=head1 NAME

Replay::EventSystem::AWSQueue - AWS Topic/Queue implimentation

=head1 VERSION

Version 0.01

head1 SYNOPSIS

This is an Event System implimentation module targeting the AWS services
of SNS and SQS.  If you were to instantiate it independently, it might 
look like this.

Replay::EventSystem::AWSQueue->new(
    purpose => $purpose,
    config  => {
        stage       => 'test',
        awsIdentity => {
            access => 'AKIAILL6EOKUCA3BDO5A',
            secret => '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',
        },
        snsService => 'https://sns.us-east-1.amazonaws.com',
        sqsService => 'https://sqs.us-east-1.amazonaws.com',
    }
);

Utilizers should expect the object instance to be a singleton per each $purpose.

The account provided is expected to have the permissions to create topics and queues.

It will create SNS topic for the indicated purpose named <stage>-replay-<purpose>

It will create distinct SQS queues for the instance, named <stage>-replay-<purpose>-<uuid>

It will also subscribe the queue to the topic.

=head1 SUBROUTINES/METHODS

=head2 subscribe( sub { my $message = shift; ... } )

each code reference supplied is called with each message received, each time
the message is recieved.  This is how applications insert their hooks into 
the channel to get notified of the arrival of messages.

=head2 emit( $message )

Send the specified message on the topic for this channel

=head2 poll()

Gets new messages and calls the subscribed hooks with them

=head2 DEMOLISH

Makes sure to properly clean up and disconnect from queues

=head1 AUTHOR

David Ihnen, C<< <davidihnen at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-replay at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Replay>.  I will be notified, and then you'

        ll automatically be notified of progress on your bug as I make changes .

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Replay


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Replay>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Replay>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Replay>

=item * Search CPAN

L<http://search.cpan.org/dist/Replay/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2014 David Ihnen.

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). You may obtain a
copy of the full license at:

L<http://www.perlfoundation.org/artistic_license_2_0>

Any use, modification, and distribution of the Standard or Modified
Versions is governed by this Artistic License. By using, modifying or
distributing the Package, you accept this license. Do not use, modify,
or distribute the Package, if you do not accept this license.

If your Modified Version has been derived from a Modified Version made
by someone other than you, you are nevertheless required to ensure that
your Modified Version complies with the requirements of this license.

This license does not grant you the right to use any trademark, service
mark, tradename, or logo of the Copyright Holder.

This license includes the non-exclusive, worldwide, free-of-charge
patent license to make, have made, use, offer to sell, sell, import and
otherwise transfer the Package with respect to any patent claims
licensable by the Copyright Holder that are necessarily infringed by the
Package. If you institute patent litigation (including a cross-claim or
counterclaim) against any party alleging that the Package constitutes
direct or contributory patent infringement, then this Artistic License
to you shall terminate on the date that such litigation is filed.

Disclaimer of Warranty: THE PACKAGE IS PROVIDED BY THE COPYRIGHT HOLDER
AND CONTRIBUTORS "AS IS' AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES.
THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE, OR NON-INFRINGEMENT ARE DISCLAIMED TO THE EXTENT PERMITTED BY
YOUR LOCAL LAW. UNLESS REQUIRED BY LAW, NO COPYRIGHT HOLDER OR
CONTRIBUTOR WILL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, OR
CONSEQUENTIAL DAMAGES ARISING IN ANY WAY OUT OF THE USE OF THE PACKAGE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut

1;
