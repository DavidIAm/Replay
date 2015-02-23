#!/usr/bin/perl

use Test::Most tests => 26;
use Test::MockObject;

# This state encapsulates the outstanding requests to create a new project
#
# ATDOMAIN rule
# The list of active domains and the keys in them that we're processing
#
# SendMessageWhen message
# kvs At alltime - { domain => '', keys => [ ] }
#
# SentMessageAt message
# kvs At alltime - { domain => '', keys => [ ] }
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
#                         'min': 1407116462',
#                         'max': 1407116462',
#                         'atdomain': 'rulename',
#                         'payload': { MessageType: '...', Message: { ... } },
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

use Replay::Rules::AtDomain;
my $r = new Replay::Rules::AtDomain;
is $r->name,    'AtDomain', 'rule name defined';
is $r->version, 2,          'rule version defined';
ok $r->match({ MessageType => 'SendMessageWhen' }), 'matches SendMessageWhen';
ok $r->match({ MessageType => 'SentMessageAt' }), 'matches SentMessageAt';
ok $r->match({ MessageType => 'Timing' }),        'matches Timing';
ok !$r->match({ MessageType => 'SomethingElse' }),
    'doesnt match other things';
is $r->window, 'alltime', 'window is alltime';
is_deeply [
    $r->key_value_set(
        {   MessageType => 'SendMessageWhen',
            Message     => { atdomain => 'adomain', newmin => 5, newmax => 5, window => '1000' }
        }
    )
    ],
    [
    '-',
    {   __TYPE__ => 'request',
        domain   => 'adomain',
        incr     => 1,
        min   => 5,
        max   => 5,
        window   => '1000'
    }
    ],
    'SendMessageWhen mutates state';
is_deeply [
    $r->key_value_set(
        {   MessageType => 'SentMessageAt',
            Message => { atdomain => 'bdomain', newmin => 2, newmax => 8, window => 1000 }
        }
    )
    ],
    [
    '-',
    {   __TYPE__ => 'confirmation',
        domain   => 'bdomain',
        incr     => -1,
        min      => 2,
        max      => 8,
        window   => 1000,
    }
    ],
    'SentMessageAt mutates state';
is_deeply [
    $r->key_value_set({ MessageType => 'Timing', Message => { epoch => '6' } }) ],
    [ '-', { __TYPE__ => 'trigger', sendnow => 1, epoch => 6 } ],
    'timing message mutates state';

# state corners:
#  - domains hash
#  nonexistant
#  empty
#  populated with matching
#  populated with nonmatching
#
#  - SendMessageWhen
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
        {   MessageType => 'SendMessageWhen',
            Message     => { atdomain => 'adomain', newmax => 5, newmin => 5, window => 1000 }
        }
    );
    my @results = $r->reduce($e, $value,);
    is_deeply [@results],
        [
        {   __TYPE__ => 'domains',
            D        => { adomain => { 1000 => { max => 5, min => 5, cnt => 1 } } }
        }
        ],
        'sendMessageAt adds to new output state';
    my ($name, $args) = $e->next_call;
    is $name, undef, 'emit is not called 2';
}

# sendmessageat when there is something already in that domain
{
    my ($key, $value) = $r->key_value_set(
        {   MessageType => 'SendMessageWhen',
            Message     => { atdomain => 'adomain', newmax => 5, newmin => 4, window => 1000 }
        }
    );
    my @results = $r->reduce(
        $e, $value,
        {   __TYPE__ => 'domains',
            D        => { adomain => { 1000 => { max => 5, min => 5, cnt => 1 } } }
        }
    );
    is_deeply [@results],
        [
        {   __TYPE__ => 'domains',
            D        => { adomain => { 1000 => { max => 5, min => 4, cnt => 2 } } }
        }
        ],
        'sendMessageAt adds to existing output state with diff domain';
    my ($name, $args) = $e->next_call;
    is $name, undef, 'emit is not called 3';
}

# sendmessagewhen there is something already in another domain
{
    my ($key, $value) = $r->key_value_set(
        {   MessageType => 'SendMessageWhen',
            Message     => { atdomain => 'bdomain', newmax => 6, newmin => 6, window => 1000 }
        }
    );
    my @results = $r->reduce(
        $e, $value,
        {   __TYPE__ => 'domains',
            D        => { adomain => { 1000 => { max => 5, min => 4, cnt => 2 } } }
        }
    );
    is_deeply [@results],
        [
        {   __TYPE__ => 'domains',
            D        => {
                adomain => { 1000 => { max => 5, min => 4, cnt => 2 } },
                bdomain => { 1000 => { max => 6, min => 6, cnt => 1 } }
            }
        }
        ],
        'SendMessageWhen adds to existing domain';
    my ($name, $args) = $e->next_call;
    is $name, undef, 'emit is not called 4';
}

# sentmessageat causes decrement and dissappear
{
    my ($key, $value) = $r->key_value_set(
        {   MessageType => 'SentMessageAt',
            Message     => {
                atdomain  => 'bdomain',
                actual    => 7,
                requested => 6,
                min       => undef,
                max       => undef,
                window    => 1000,
            }
        }
    );
    my @results = $r->reduce($e, $value);
    my @results = $r->reduce(
        $e, $value,
        {   __TYPE__ => 'domains',
            D        => {
                adomain => { 1000 => { cnt => 1, min => 1, max => 9 } },
                bdomain => { 1000 => { cnt => 1, min => 1, max => 9 } }
            }
        }
    );
    is_deeply [@results],
        [
        {   __TYPE__ => 'domains',
            D        => { adomain => { 1000 => { max => 9, min => 1, cnt => 1 } } }
        },
        ],
        'SentMessageAt removes single count state';
    my ($name, $args) = $e->next_call;
    is $name, undef, 'emit is not called 5';
}

# sentmessageat causes decrement and minmax reset
{
    my ($key, $value) = $r->key_value_set(
        {   MessageType => 'SentMessageAt',
            Message     => {
                atdomain  => 'adomain',
                actual    => 7,
                requested => 5,
                newmin    => 6,
                newmax    => 6,
                window    => 1000,
            }
        }
    );
    my @results = $r->reduce(
        $e, $value,
        {   __TYPE__ => 'domains',
            D        => { adomain => { 1000 => { cnt => 2, min => 1, max => 9 } } }
        }
    );
    is_deeply [@results],
        [
        {   __TYPE__ => 'domains',
            D        => { adomain => { 1000 => { max => 6, min => 6, cnt => 1 } } }
        },
        ],
        'SentMessageAt decrements exsisting multipel count state and updates minmax';
    my ($name, $args) = $e->next_call;
    is $name, undef, 'emit is not called 6';
}

# timing causes emit of SendMessageNow for matching entries
{
    my ($key, $value)
        = $r->key_value_set(
        { MessageType => 'Timing', Message => { epoch => '5' } });
    my @results = $r->reduce(
        $e, $value,
        {   __TYPE__ => 'domains',
            D        => {
                adomain => { 1000 => { max => 5, min => 4, cnt => 2 } },
                bdomain => { 1000 => { max => 6, min => 6, cnt => 1 } }
            }
        }
    );
    is_deeply [@results],
        [
        {   __TYPE__ => 'domains',
            D        => {
                adomain => { 1000 => { max => 5, min => 4, cnt => 2 } },
                bdomain => { 1000 => { max => 6, min => 6, cnt => 1 } }
            }
        },
        ],
        'Timing message causes no shift';
    {
        my ($name, $args) = $e->next_call;
        is $name, 'emit', 'emit is called';
        my $m  = $args->[2]->marshall;
        my $mm = $m->{Message};
        is_deeply $mm, { sendtime => 5, atdomain => 'adomain', window => 1000 },
            'submessage emitted is as expected';
        delete $m->{EffectiveTime};
        delete $m->{CreatedTime};
        delete $m->{Message};
        delete $m->{Replay};
        delete $m->{UUID};
        delete $m->{ReceivedTime};
        is_deeply $m, { MessageType => 'SendMessageNow' },
            'it emits a SendMessageNow message';
    }
}

