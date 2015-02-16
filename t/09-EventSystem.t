
use Test::Most qw/no_plan bail/;

use_ok 'Replay';

my $es = Replay::EventSystem->new(
    config => {
        stage       => 'testrabbit',
        EventSystem => {
            Mode     => 'RabbitMQ',
            RabbitMQ => {
                host    => 'localhost',
                options => {
                    port     => '5672',
                    user     => 'testuser',
                    password => 'testpass',

                    #            user    => 'replay',
                    #            pass    => 'replaypass',
                    #vhost   => 'replay',
                    vhost       => '/testing',
                    timeout     => 30,
                    tls         => 1,
                    heartbeat   => 1,
                    channel_max => 0,
                    frame_max   => 131072
                },
            },
        }
    }
);

isa_ok $es, 'Replay::EventSystem';

is $es->mode, 'Replay::EventSystem::RabbitMQ';

ok $es->origin->does('Replay::EventSystem::Base');
is $es->origin->purpose, 'origin';
ok $es->derived->does('Replay::EventSystem::Base');
is $es->derived->purpose, 'derived';
ok $es->control->does('Replay::EventSystem::Base');
is $es->control->purpose, 'control';
ok $es->originsniffer->does('Replay::EventSystem::Base');
is $es->origin->purpose, 'origin';
ok $es->derivedsniffer->does('Replay::EventSystem::Base');
is $es->derived->purpose, 'derived';

use Data::Dumper;

foreach ($es->origin, $es->derived, $es->control) {
    ok $_->can('emit'),      'can emit';
    ok $_->can('subscribe'), 'can subscribe';
    ok $_->can('poll'),      'can poll';
    ok $_->can('rabbit'),    'can rabbit';
    ok defined $_->rabbit, "rabbit is defined " . $_->purpose;
    my $pre  = 0;
    my $post = 0;
    $_->subscribe(sub { $pre++ });
    $_->subscribe(sub { die 'exceptioncase' });
    $_->subscribe(sub { $post++ });
    $_->emit(Replay::Message->new(MessageType => 'bark', dog => 'woof'));
    $_->poll();
    ok $pre,  'presubscribe called';
    ok $post, 'postsubscribe called';
}

