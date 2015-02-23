
use Test::Most qw/no_plan bail/;
use Test::MockModule;
use Test::MockObject::Extends;

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
use Test::MockObject::Extends;

foreach ($es->origin, $es->derived, $es->control) {
    ok $_->can('emit'),      'can emit';
    ok $_->can('subscribe'), 'can subscribe';
    ok $_->can('poll'),      'can poll';
    ok $_->can('rabbit'),    'can rabbit';
    ok defined $_->rabbit, "rabbit is defined " . $_->purpose;
    my ($ack, $nack) = (0,0);
    my $specialpoller = Test::MockObject::Extends->new( $_ );
    $specialpoller->mock('_receive', sub { 
        my $e = Test::MockObject->new();
        $e->mock('ack', sub { $ack++ }); 
        $e->mock('nack', sub { $nack++ }); 
        $e->mock('body', sub { {} });
        return $e;
      } );
    $specialpoller->subscribe(sub { 1 });
    $specialpoller->subscribe(sub { die 'exceptioncase' });
    $specialpoller->subscribe(sub { 0 });
    $specialpoller->emit(Replay::Message->new(MessageType => 'bark', dog => 'woof'));
    $specialpoller->poll();
    is $ack,  2, 'ack called';
    is $nack, 1, 'nack called';
}

