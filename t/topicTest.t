#!/usr/bin/perl
#

use Amazon::SNS;
use Amazon::SQS::Simple;
use Data::Dumper;
use Data::UUID;
use JSON;

# my creds (cg_web_server or 102957800988)
my $accesskey  = 'AKIAJUZLBY2RIDB6LSJA';
my $secret     = '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';
my $snsservice = 'https://sns.us-east-1.amazonaws.com';
my $sqsservice = 'https://sqs.us-east-1.amazonaws.com';

my $sns = Amazon::SNS->new({ key => $accesskey, secret => $secret });

# if you don't set this, it might end up in europe or something
$sns->service($snsservice);

# Predefined well-known topic ARN
my $topic = $sns->GetTopic('arn:aws:sns:us-east-1:102957800988:test_topic');
die unless $topic;

warn "topic" . Dumper $topic;
warn "subscribing";

# Create us a new queue
my $sqs = new Amazon::SQS::Simple($accesskey, $secret);

# with a unique name
my $ug   = Data::UUID->new;
my $name = 'test_queue_' . $ug->to_string($ug->create);
my $q    = $sqs->CreateQueue($name);

# The SQS module makes it awkward to get the ARN.  I create it manually here, but there's probably a better way?
my $qarn = 'arn:aws:sqs:us-east-1:102957800988:' . $name;

# Set the policy on the queue to allow the topic to publish to it
print "SetQueueAttributes";
my $policy = to_json(
    {   "Version"   => "2012-10-17",
        "Statement" => [
            {   "Sid"       => "MySQSPolicy$name",
                "Effect"    => "Allow",
                "Principal" => { "AWS" => "*" },
                "Action"    => "sqs:SendMessage",
                "Resource"  => $qarn,
                "Condition" => { "ArnEquals" => { "aws:SourceArn" => $topic->arn } }
            }
        ]
    }
);
print Dumper $policy;
print Dumper $q->SetAttribute('Policy', $policy);

# This is what the SQS module DOEs provide - the url of the endpoint.
# maybe we should parse the principal out of it?
warn "ENDPOINT" . $q->Endpoint;
use Data::Dumper;

# The actual subscribe command
my $subres = $sns->dispatch(
    {   Action   => 'Subscribe',
        Endpoint => 'arn:aws:sqs:us-east-1:102957800988:' . $name,
        Protocol => 'sqs',
        TopicArn => $topic->arn
    }
);

# We can use the subscription ARN to unsubscribe later
my $subARN = $subres->{'SubscribeResult'}{'SubscriptionArn'};
warn "the arn of sub is $subres->{'SubscribeResult'}{'SubscriptionArn'}";

warn "publishing";

# This is how we publish to the topic.  Real simple, right?  It can also be a complex json thing with different messages for each protocol!
# Publish(MESSAGE, SUBJECT)
print Dumper $topic->Publish('test message', 'control');
warn "was the publish";

# wait a sec to make sure things propagate
sleep 1;

# Check the queue for messages
warn "Recieving";
my $m = $q->ReceiveMessage;

print Dumper $m;

# Issue the unsubscribe to remove it from the list of subscriptions on the topic
print "UNSUBSCRIBE RESPOSNE: ";
print Dumper $sns->dispatch(
    { Action => 'Unsubscribe', SubscriptionArn => $subARN });

# Issue the delete queue since we won't be needing this test queue any more.
print "DELETE RESPONSE: " . Dumper $q->Delete;

#$topic->DeleteTopic;

