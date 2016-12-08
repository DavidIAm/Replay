package reducerTest;

use Test::Most;
use Test::MockObject::Extends;
use Test::Mock::Class ':all';
use Replay::Reducer;
use Replay::EventSystem::Null;
use Replay::Message::Reducable;
use base qw(Test::Class);

sub make_support : Test(setup) {
    my ($self) = @_;
    mock_class 'Replay::RuleSource';
    mock_class 'Replay::StorageEngine';
    mock_class 'Replay::EventSystem';
    mock_class 'Replay::EventSystem::Null';
    $self->{reducevents} = Replay::EventSystem::Null::Mock->new(
        purpose => 'reduce',
        config  => { EventSystem => { Mode => 'Mock::Null' } },
        mode    => 'topic'
    );
    $self->{eventsystem} = Replay::EventSystem->new(
        reduce => $self->{reducevents},
        config => { EventSystem => { Mode => 'Null' } }
    );
    $self->{reduce} = Replay::EventSystem::Null->new(
        mode    => 'worker',
        config  => {},
        purpose => 'reduce'
    );
    $self->{rulesource} = Replay::RuleSource::Mock->new(
        eventSystem => $self->{eventsystem} );
    $self->{storageengine} = Replay::StorageEngine::Mock->new(
        config      => {},
        eventSystem => $self->{eventsystem},
        ruleSource  => $self->{rulesource}
    );
    $self->{subscriptions} = [];

    #    $self->{eventreducer}->mock_return(
    #        subscribe => sub { push @{ $self->{subscriptions} }, pop },
    #        args => [ $self->{reducerwrapper} ]
    #    );
    $self->{reducerwrapper} = sub { };
}

sub make_reducer {
    my ( $self, @config ) = @_;
    mock_class 'Replay::Reducer';
    $self->{reducer} = Replay::Reducer->new(
        {   config        => {@config},
            ruleSource    => $self->{rulesource},
            eventSystem   => $self->{eventsystem},
            storageEngine => $self->{storageengine}
        }
    );
}

sub BUILD : Test(1) {
    my ($self) = @_;

    $self->{reducevents}->mock_expect_minimum_call_count( 'subscribe', 1 );
    $self->{reducevents}->mock_expect_minimum_call_count( 'emit',      1 );

    $self->make_reducer;

    $self->{eventsystem}
        ->emit( 'reduce', { MessageType => 'test', message => 1 } );

    $self->{reducevents}->mock_tally;
}

sub NULL_FILTER_ENABLED : Test(3) {
    my ($self) = @_;
    $self->make_reducer();
    ok !$self->{reducer}->NULL_FILTER_ENABLED(),
        'null filter disabled by default';
    $self->make_reducer( null_filter_enabled => 0 );
    ok !$self->{reducer}->NULL_FILTER_ENABLED(),
        'null filter enabled when disabled';
    $self->make_reducer( null_filter_enabled => 1 );
    ok $self->{reducer}->NULL_FILTER_ENABLED(),
        'null filter enabled when enabled';
}

sub ARRAYREF_FLATTEN_ENABLED : Test(3) {
    my ($self) = @_;
    $self->make_reducer();
    ok !$self->{reducer}->ARRAYREF_FLATTEN_ENABLED(),
        'arrayref flatten disabled by default';
    $self->make_reducer( arrayref_flatten_enabled => 0 );
    ok !$self->{reducer}->ARRAYREF_FLATTEN_ENABLED(),
        'arrayref flatten enabled when disabled';
    $self->make_reducer( arrayref_flatten_enabled => 1 );
    ok $self->{reducer}->ARRAYREF_FLATTEN_ENABLED(),
        'arrayref flatten enabled when enabled';
}

sub rule : Test(2) {
    my ($self) = @_;
    $self->{rulesource}->mock_expect_minimum_call_count( 'by_idkey', 1 );

    $self->make_reducer(
        null_filter_enabled      => 0,
        arrayref_flatten_enabled => 0
    );

    $self->{reducer}->rule(
        Replay::IdKey->new(
            name    => 'name',
            version => 'version',
            window  => 'window',
            key     => 'key'
        )
    );

    $self->{rulesource}->mock_tally;
}

sub normalize_envelope : Test(4) {
    my ($self) = @_;
    my $r = $self->make_reducer;
    is $r->normalize_envelope(), undef;
    isa_ok $r->normalize_envelope(
        MessageType => 'bark',
        Message     => { sound => 'woof' }
        ),
        'Replay::Message';
    isa_ok $r->normalize_envelope(
        { MessageType => 'bark', Message => { sound => 'woof' } } ),
        'Replay::Message';
    isa_ok $r->normalize_envelope(
        Replay::Message->new(
            { MessageType => 'bark', Message => { sound => 'woof' } }
        )
        ),
        'Replay::Message';
}

sub reducable_message : Test(2) {
    my ($self) = @_;
    my $r = $self->make_reducer;
    ok $r->reducable_message(
        Replay::Message::Reducable->new(
            name    => 'n',
            version => '1',
            window  => 'w',
            key     => 'k'
        )
        ),
        'Reducable message is reducable';
    ok !$r->reducable_message(
        Replay::Message->new( 'MessageType' => 'SOMETHINGELSE' ) );
}

sub identify : Test(5) {
    my ($self) = @_;
    my $mock = Test::MockObject::Extends->new(
        Replay::Message->new( MessageType => 'MockMessage' ) );
    $mock->set_always( 'name' => 'mockname' )
        ->set_always( 'version' => 'mockversion' )
        ->set_always( 'window'  => 'mockwindow' )
        ->set_always( 'key'     => 'mockkey' );
    my $id = $self->make_reducer->identify($mock);
    isa_ok $id, 'Replay::IdKey';
    is $id->name,    'mockname';
    is $id->version, 'mockversion';
    is $id->window,  'mockwindow';
    is $id->key,     'mockkey';
}

sub reduce_wrapper : Test(1) {
    my ($self) = @_;
    my $reducer = Test::MockObject::Extends->new( $self->make_reducer );
    $reducer->set_true('reducable_message')
        ->mock( 'normalize_envelope', sub { shift; shift } )
        ->mock( 'execute_reduce', sub { isa_ok Replay::IdKey } );
    $reducer->reduce_wrapper(
        Replay::Message::Reducable->new(
            {   name    => 'name',
                version => 'version',
                window  => 'window',
                key     => 'key',
            }
        )
    );
}

package main;

reducerTest->runtests;

=pod

sub ARRAYREF_FLATTEN_ENABLED_DEFAULT {1}
sub NULL_FILTER_ENABLED_DEFAULT      {1}
sub NULL_FILTER_ENABLED 
sub ARRAYREF_FLATTEN_ENABLED 
sub BUILD 
sub rule 
sub reduce_wrapper 
sub arrayref_flatten 
sub null_filter 

=end
