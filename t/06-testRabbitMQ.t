package Test::RabbitMQ;

use Test::Most;
use Data::Dumper;
use Net::RabbitMQ;
use JSON qw/to_json from_json/;

my $rabbit = Net::RabbitMQ->new;

isa_ok $rabbit, 'Net::RabbitMQ';

#my $connected = $rabbit->connect('localhost', { user => 'testuser', password => 'testpass', vhost => '/testing' });
#my $connected = $rabbit->connect('localhost', { user => 'replay', password => 'replaypass', vhost => '/replay' });
my $connected = $rabbit->connect('localhost', {
                          'frame_max' => 131072,
                         'password' => 'replaypass',
                         'port' => '5672',
                         'user' => 'replay',
                         'vhost' => '/replay',
                         'channel_max' => 0,
                         'timeout' => 30,
                         'heartbeat' => 1,
                         'tls' => 1
                       }),

 

lives_ok sub { $rabbit->channel_open(2) };
lives_ok sub { $rabbit->channel_open(3) };

lives_ok sub { $rabbit->exchange_declare( 2, 'my exchange', { auto_delete => 1 }) };

lives_ok sub { $rabbit->publish(2, 'animal.sounds', "CAT CAT ", { exchange => 'my exchange' } ) };

lives_ok sub { $rabbit->queue_declare( 3, 'my queue', { auto_delete => 0 }) };
lives_ok sub { $rabbit->queue_bind( 3, 'my queue', 'my exchange', 'nr_test_route') };

lives_ok sub { $rabbit->publish(2, 'nr_test_route', "dog => 'woof'", { exchange => 'my exchange' }) };

#lives_ok sub { warn Dumper $rabbit->consume(3, 'my queue', { consumer_tag => 'ctag' }) };
#lives_ok sub { warn Dumper $rabbit->recv };
lives_ok sub { warn "GET " . Dumper $rabbit->get(3, 'my queue') };

use strict;

my $dtag=(unpack("L",pack("N",1)) != 1)?'0100000000000000':'0000000000000001';
my $host = 'localhost';

use_ok('Net::RabbitMQ');

my $mq = Net::RabbitMQ->new();
ok($mq);

eval { $mq->connect($host, { user => "guest", password => "guest" }); };
is($@, '', "connect");
eval { $mq->channel_open(1); };
is($@, '', "channel_open");
my $queuename = '';
eval { $queuename = $mq->queue_declare(1, '', { passive => 0, durable => 1, exclusive => 0, auto_delete => 1 }); };
is($@, '', "queue_declare");
isnt($queuename, '', "queue_declare -> private name");
eval { $mq->queue_bind(1, $queuename, "nr_test_x", "nr_test_q"); };
is($@, '', "queue_bind");
eval { $mq->publish(1, "nr_test_q", "Magic Transient Payload", { exchange => "nr_test_x" }); };
is($@, '', "publish");
eval { $mq->consume(1, $queuename, {consumer_tag=>'ctag', no_local=>0,no_ack=>1,exclusive=>0}); };
is($@, '', "consume");

my $rv = {};
eval { $rv = $mq->recv(); };
warn Dumper $rv;
is($@, '', "recv");
$rv->{delivery_tag} =~ s/(.)/sprintf("%02x", ord($1))/esg;
is_deeply($rv,
          {
          'body' => 'Magic Transient Payload',
          'routing_key' => 'nr_test_q',
          'delivery_tag' => $dtag,
          'exchange' => 'nr_test_x',
          'consumer_tag' => 'ctag',
          'props' => {},
          }, "payload");

done_testing();

