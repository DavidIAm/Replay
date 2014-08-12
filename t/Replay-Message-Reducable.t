use base 'Test::Class';
use Test::Most;

use Replay::Message::Reducable;
use Data::Dumper;

sub A_instance : Test(6) {
    my $message = Replay::Message::Reducable->new(
        domain  => 'a',
        name    => 'b',
        version => 'c',
        window  => 'd',
        key     => 'e'
    );
    isa_ok $message, 'Replay::Message::Reducable', "message";
    ok $message->can('pack'), "can pack";
    my $struct = $message->marshall;
    ok defined delete $struct->{CreatedTime};
    ok defined delete $struct->{UUID};
    ok defined delete $struct->{ReceivedTime};
    is_deeply $struct,
        {
        'Message' => {
            'domain'  => 'a',
            'window'  => 'd',
            'version' => 'c',
            'name'    => 'b',
            'key'     => 'e'
        },
        'MessageType' => 'Reducable',
        },
        "message matches expectation";

}

__PACKAGE__->runtests;
