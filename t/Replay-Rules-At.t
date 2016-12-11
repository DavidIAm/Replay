#!/usr/bin/perl
package SURELY;

use Moose;
use MooseX::MetaDescription::Meta::Trait;
with qw/Replay::Role::Envelope/;

has '+MessageType' => ( default => 'SURELY' );
has 'surely' => (
    is          => 'ro',
    isa         => 'Str',
    traits      => ['MooseX::MetaDescription::Meta::Trait'],
    description => { layer => 'message' },
);

package Main;

use Test::Most;    # tests => 25;
use Test::MockObject;

plan skip_all => 'todo at';

=pod

# This state encapsulates the outstanding requests to send a message
# AT a particular time
#
# ATDOMAIN rule
# The list of active domains and the keys in them that we're processing
#
# SendMessageAt message
# kvs At cielingwindow atdomain => { sendat => ####,  }
#
# SentMessageAt message generated
# Pkvs At alltime - { domain => '', keys => [ ] }
#
# Timing message
# kvs At alltime - { timing }
#
# reduce
#   add up domain values.  drop if 0.
#   drop timing message input
#   iterate all nonzero domains
#     if key is less than time
#      emit SentMessageAt { requested, actual, atdomain, time }
#
# send domain specific message for each atdomain/window
# manage the list of atdomains/windows
# increment atdomain/window
# decrement atdomain/window

#$VAR1 = {
#          'Replay' => '20140727',
#          'MessageType' => 'SendMessageWhen',
#          'Message' => {
#                         'newmin': 1407116462',
#                         'newmax': 1407116462',
#                         'window': 1407116000',
#                         'atdomain': 'rulename',
#                       },
#        };
# $VAR2 = {
#          'Replay' => '20140727',
#          'MessageType' => 'SentMessageAt',
#          'Message' => {
#                         'requested': 1407116462',
#                         'actual': 1407116462',
#                         'atdomain': 'rulename',
#                         'sentuuid': 'DFJAKLDJFALDSKF',
#                         'foruuid': 'DFJAKLDJFALDSKF',
#                         'payload': { MessageType: '...', Message: { ... } },
#                       },
#        }
# $VAR2 = {
#          'Replay' => '20140727',
#          'MessageType' => 'Timing',
#          'Message' => {
#                         'epoch' => '1407116462',
#                       },
#        }
# $VAR3 = {
#          'Replay' => '20140727',
#          'MessageType' => 'SendMessageNow',
#          'Message' => {
#                       'epoch' => '1407116462',
#                       'window' => '1407117000',
#                       'atdomain': 'rulename',
#                       },
#        };

#use Replay::Rules::At;
#my $r = new Replay::Rules::At;

use Replay::Rules::At;
my $r = new Replay::Rules::At;
is $r->name,    'At', 'rule name defined';
is $r->version, 2,    'rule version defined';
ok $r->match({ MessageType => 'SendMessageAt' }),  'matches SendMessageAt';
ok $r->match({ MessageType => 'SendMessageNow' }), 'matches SendMessageNow';
ok !$r->match({ MessageType => 'Timing' }), 'does not match Timing';
ok !$r->match({ MessageType => 'SomethingElse' }),
    'doesnt match other things';
is $r->window(
    { MessageType => 'SendMessageAt', Message => { sendat => 12345 } }), 13000,
    'window is 13000';
is $r->window(
    { MessageType => 'SendMessageNow', Message => { window => 52345 } }), 52345,
    'window is whatever noted';
is_deeply [
    $r->key_value_set(
        {   MessageType => 'SendMessageAt',
            Message =>
                { atdomain => 'adomain', sendat => 5, payload => { cat => 'doll' } },
            UUID => 'notreally',
        }
    )
    ],
    [
    'adomain',
    {   atdomain => 'adomain',
            requested => 0,
        window   => 1000,
        sendat   => 5,
        uuid     => 'notreally',
        payload  => { cat => 'doll' }
    }
    ],
    'SendMessageAt mutates state';
is_deeply [
    $r->key_value_set(
        {   MessageType => 'SendMessageNow',
            Message =>
                { atdomain => 'bdomain', window => 'somewindow', sendtime => 17171717 }
        }
    )
    ],
    [ 'bdomain', { atdomain => 'bdomain', epoch => 17171717, } ],
    'SendMessageNow mutates state';

# state corners:
#  - domains hash
#  nonexistant
#  empty
#  populated with matching
#  populated with nonmatching
#
#  - SendMessageAt
#  single present
#  not present
#  multiple present
#
#  - SentMessageAt
#  single present
#  not present
#  multiple present
#
#  - Timing
#  not present
#  single present
#  multiple present

my $e = new Test::MockObject;

$e->mock('emit');

# timing when there is nothing to do
{
    my ($key, $value)
        = $r->key_value_set({ MessageType => 'Timing', Message => { epoch => 5 } });
    my @results = $r->reduce($e, $value);
    is_deeply [@results], [], 'timing does not change state';
    my ($name, $args) = $e->next_call;
    is $name, undef, 'emit is not called 1';
}

# sendmessageat when there is nothing yet
{
    my ($key, $value) = $r->key_value_set(
        {   MessageType => 'SendMessageAt',
            Message     => {
                atdomain => 'adomain',
                sendat   => 1005,
                channel  => 'origin',
                payload  => { surely => 'yes' }
            },
            UUID => 'notreally',
        }
    );
    my @results = $r->reduce($e, $value,);
    is_deeply [@results], [
        {   window   => '2000',
            atdomain => 'adomain',
            sendat   => 1005,
            channel  => 'origin',
            payload  => { surely => 'yes' },
            requested => 0,
            uuid => 'notreally',
        }
        ],
        'sendMessageAt adds to new output state';
    {
        my ($name, $args) = $e->next_call;
        is $name, 'emit', 'emit is called';
        my $m  = $args->[2]->marshall;
        my $mm = $m->{Message};
        is_deeply $mm, { atdomain => 'adomain', window => 2000 }, 'submessage emitted is as expected';
        delete $m->{CreatedTime};
        delete $m->{Replay};
        delete $m->{UUID};
        delete $m->{ReceivedTime};
        is_deeply $m, { MessageType => 'SendMessageWhen', Message => { atdomain => 'adomain', window => '2000' } },
            'it emits a SendMessageWhen message';
    }{
        my ($name, $args) = $e->next_call;
        is $name, undef, 'emit is not called';
    }

}

# sendmessagenow causes removal and emit
{
    my ($key, $value) = $r->key_value_set(
        {   MessageType => 'SendMessageAt',
            Message     => {
                atdomain => 'adomain',
                sendat   => 1005,
                channel  => 'origin',
                payload  => { surely => 'yes' },
                class    => 'SURELY'
            },
            UUID => 'notreally',
        }
    );
    my ($key2, $value2) = $r->key_value_set(
        {   MessageType => 'SendMessageAt',
            Message     => {
                atdomain => 'adomain',
                sendat   => 1008,
                channel  => 'origin',
                payload  => { surely => 'yes' },
                class    => 'SURELY'
            },
            UUID => 'notreallya',
        }
    );
    my ($key3, $value3) = $r->key_value_set(
        {   MessageType => 'SendMessageNow',
            Message     => { atdomain => 'bdomain', sendtime => 1006, }
        }
    );
    my @results = $r->reduce($e, $value, $value2, $value3);
    delete $results[0]{class};
    is_deeply [@results], [$value2], 'SentMessageAt removes single count state';
    {
        my ($name, $args) = $e->next_call;
        is $name, 'emit', 'emit is called';
        my $m  = $args->[2]->marshall;
        my $mm = $m->{Message};
        is_deeply $mm, { surely => 'yes' }, 'submessage emitted is as expected';
        delete $m->{CreatedTime};
        delete $m->{Replay};
        delete $m->{UUID};
        delete $m->{ReceivedTime};
        is_deeply $m, { MessageType => 'SURELY', Message => { surely => 'yes', } },
            'it emits a SURELY message';
    }
    {
        my ($name, $args) = $e->next_call;
        is $name, 'emit', 'emit is called';
        my $m  = $args->[2]->marshall;
        my $mm = $m->{Message};
        delete $m->{CreatedTime};
        delete $m->{Replay};
        delete $m->{UUID};
        delete $m->{ReceivedTime};
        ok delete $mm->{actual},   'actual was set';
        ok delete $mm->{sentuuid}, 'sentuuid was set';
        is_deeply $m,
            {
            MessageType => 'SendMessageAt',
            Message     => {
                atdomain  => 'adomain',
                foruuid   => 'notreally',
                window    => 2000,
                requested => 1005,
                newmin    => 1008,
                newmax    => 1008,
            }
            },
            'it emits a SendMessageNow message';
    }
}

1;
