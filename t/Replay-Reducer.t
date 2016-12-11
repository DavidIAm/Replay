package Test::Replay::Reducer;

use Test::Most;
use Test::Output;
use Test::MockObject::Extends;
use Test::Mock::Class ':all';
use Replay::Reducer;
use Replay::EventSystem::Null;
use Replay::Message::Reducable;
use base qw(Test::Class);

sub make_support : Test(setup) {
    my ($self) = @_;
    mock_class 'Replay::IdKey';
    mock_class 'Replay::RuleSource';
    mock_class 'Replay::StorageEngine';
    mock_class 'Replay::EventSystem';
    mock_class 'Replay::DelayedEmitter';
    mock_class 'Replay::EventSystem::Null';
    mock_class 'Replay::Message::Reduced';
    $self->{reducevents} = Replay::EventSystem::Null::Mock->new(
        purpose => 'reduce',
        config  => { EventSystem => { Mode => 'Mock::Null' } },
        mode    => 'topic'
    );
    $self->{controlevents} = Replay::EventSystem::Null::Mock->new(
        purpose => 'control',
        config  => { EventSystem => { Mode => 'Mock::Null' } },
        mode    => 'topic'
    );
    $self->{idkey} = Replay::IdKey::Mock->new(
        name    => 'nm',
        version => '11',
        window  => 'serta',
        key     => 'schlage'
    );
    $self->{idkey}->mock_return(
        marshall => sub {
            (   name    => 'nm',
                version => '11',
                window  => 'serta',
                key     => 'schlage',
                UUID    => 'mockuuid/',
            );
        }
    );
    $self->{reducedmessage} = Replay::Message::Reduced->new(
name    => 'mn',
        version => 'vrsn',
    );
    $self->{eventsystem} = Replay::EventSystem->new(
        reduce  => $self->{reducevents},
        control => $self->{controlevents},
        config  => { EventSystem => { Mode => 'Null' } }
    );
    $self->{delayedemitter} = Replay::DelayedEmitter::Mock->new(
        eventSystem  => $self->{eventsystem},
        Windows      => [],
        Timeblocks   => [],
        Ruleversions => [],
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
    ok 1;

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

sub rule : Test(1) {
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

    ok 1, 'errors handled by exception on failure to call'; 
    $self->{rulesource}->mock_tally;
}

sub normalize_envelope : Test(4) {
    my ($self) = @_;
    my $r = $self->make_reducer;
    is $r->normalize_envelope(), undef;
    isa_ok + $r->normalize_envelope(
        MessageType => 'bark',
        Message     => { sound => 'woof' }
        ),
        'Replay::Message';
    isa_ok
        + $r->normalize_envelope(
        { MessageType => 'bark', Message => { sound => 'woof' } } ),
        'Replay::Message';
    isa_ok + $r->normalize_envelope(
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
        Replay::Message->new( MessageType => 'MockMessage',
        'Message' => {
            'name'    => 'mockname',
            'version' => 'mockversion',
            'window'  => 'mockwindow',
            'key'     => 'mockkey'
        })
    );
    my $id = $self->make_reducer->identify($mock);
    isa_ok $id, 'Replay::IdKey';
    is $id->name,    'mockname';
    is $id->version, 'mockversion';
    is $id->window,  'mockwindow';
    is $id->key,     'mockkey';
}

sub reduce_wrapper : Test(2) {
    my ($self) = @_;
    my $reducer = Test::MockObject::Extends->new( $self->make_reducer );
    $reducer->mock(
        'reducable_message' => sub {
            shift; shift->MessageType eq 'Reducable';
        }
        )->mock( 'normalize_envelope', sub { shift; shift } )->mock(
        'execute_reduce',
        sub { shift; is +shift, $self->{idkey}, 'mock acquired' }
        )->mock(
        'identify',
        sub {
            shift;
            isa_ok +shift, 'Replay::Message::Reducable';
            $self->{idkey};
        }
        );
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

sub execute_reduce_nouuid : Test(2) {
    my ($self) = @_;

    $self->{storageengine}
        = Test::MockObject::Extends->new( $self->{storageengine} );
    my $reducer = $self->make_reducer;
    $self->{storageengine}->mock(
        'fetch_transitional_state' => sub {
            shift;
            is +shift, $self->{idkey};
            return;
        }
    );
    is_deeply [], [ $reducer->execute_reduce( $self->{idkey} ) ];
}

sub execute_reduce_exception_fetch : Test(4) {
    my ($self) = @_;

    $self->{idkey} = Test::MockObject::Extends->new( $self->{idkey} );
    $self->{idkey}->mock(
        hash_list => sub {
            name => 'a', version => 12, window => 'serta', key => 'quikset';
        }
    );
    $self->{storageengine}
        = Test::MockObject::Extends->new( $self->{storageengine} );

    $self->{storageengine}->mock(
        'fetch_transitional_state' => sub {
            die "test fetch die";
        }
        )->mock(
        'revert',
        sub {
            shift;
            is +shift, $self->{idkey}, 'revert with idkey';
            is +shift, undef, 'and no uuid';
        }
        );
    $self->{controlevents}->mock_expect_minimum_call_count( 'emit', 1 );
    my $reducer = $self->make_reducer;
    stderr_like {
        is_deeply [], [ $reducer->execute_reduce( $self->{idkey} ) ];
    }
    qr/REDUCING EXCEPTION.+test fetch die/, 'reducing exception';
    $self->{controlevents}->mock_tally;
}

sub execute_reduce_exception_store : Test(7) {
    my ($self) = @_;

    $self->{idkey} = Test::MockObject::Extends->new( $self->{idkey} );
    $self->{idkey}->mock(
        hash_list => sub {
            name => 'a', version => 12, window => 'serta', key => 'quikset';
        }
    );
    $self->{storageengine}
        = Test::MockObject::Extends->new( $self->{storageengine} );

    $self->{storageengine}->mock(
        'fetch_transitional_state' => sub {
            'mockuuid', { META => 'data' }, 1, 2, 3, 4, 5;
        }
        )->mock(
        'revert',
        sub {
            shift;
            is +shift, $self->{idkey}, 'revert with idkey';
            is +shift, 'mockuuid', 'and with mock uuid';
        }
        )->mock(
        'store_new_canonical_state' => sub {
            die "store die";
        }
        );
    $self->{controlevents}->mock_expect_minimum_call_count( 'emit', 1 );

    my $rule = Test::MockObject::Extends->new( bless {}, 'Rule' );
    $rule->mock(
        reduce => sub {
            shift;
            is +shift, $self->{delayedemitter}, 'reduce called with emitter';
            is_deeply [@_], [ 1, 2, 3, 4, 5 ], 'and expected data';
        }
    );
    my $reducer = Test::MockObject::Extends->new( $self->make_reducer );
    $reducer->mock(
        make_delayed_emitter => sub {
            $self->{delayedemitter};
        }
        )->mock(
        rule => sub {
            shift;
            is +shift, $self->{idkey}, 'rule called with idkey';
            $rule;
        }
        );
    stderr_like {
        is_deeply [], [ $reducer->execute_reduce( $self->{idkey} ) ];
    }
    qr/REDUCING EXCEPTION.+store die/, 'storing exception';
    $self->{controlevents}->mock_tally;
}

sub execute_reduce_exception_reduce : Test(5) {
    my ($self) = @_;

    $self->{idkey} = Test::MockObject::Extends->new( $self->{idkey} );
    $self->{idkey}->mock(
        hash_list => sub {
            name => 'a', version => 12, window => 'serta', key => 'quikset';
        }
    );
    $self->{storageengine}
        = Test::MockObject::Extends->new( $self->{storageengine} );

    $self->{storageengine}->mock(
        'fetch_transitional_state' => sub {
            'mockuuid', { META => 'data' }, 1, 2, 3, 4, 5;
        }
        )->mock(
        'revert',
        sub {
            shift;
            is +shift, $self->{idkey}, 'revert with idkey';
            is +shift, 'mockuuid', 'and with mock uuid';
        }
        )->mock(
        'store_new_canonical_state' => sub {
            ok 0, "this should never hit"

                #$self->storageEngine->store_new_canonical_state(
                #$idkey, $uuid, $emitter,
                #$self->arrayref_flatten(
        }
        );
    $self->{controlevents}->mock_expect_minimum_call_count( 'emit', 1 );
    my $rule = Test::MockObject::Extends->new( bless {}, 'Rule' );
    $rule->mock(
        reduce => sub {
            shift;
            is +shift, $self->{delayedemitter}, 'reduce called with emitter';
            is_deeply [@_], [ 1, 2, 3, 4, 5 ], 'and expected data';
        }
    );
    my $reducer = Test::MockObject::Extends->new( $self->make_reducer );
    $reducer->mock(
        make_delayed_emitter => sub {
            $self->{delayedemitter};
        }
        )->mock(
        rule => sub {

            sub Rule::reduce {
                die "reduce exception direct";
            }
            shift;
            is +shift, $self->{idkey}, 'rule called with idkey';
            bless {}, 'Rule';
        }
        );
    stderr_like {
        is_deeply [], [ $reducer->execute_reduce( $self->{idkey} ) ];
    }
    qr/REDUCING EXCEPTION.+reduce exception direct/, 'reduce exception';
    $self->{controlevents}->mock_tally;
}

sub execute_reduce_success : Test(12) {
    my ($self) = @_;

    $self->{idkey} = Test::MockObject::Extends->new( $self->{idkey} );
    $self->{idkey}->mock(
        hash_list => sub {
            name => 'a', version => 12, window => 'serta', key => 'quikset';
        }
        )->mock(
        marshall => sub {
            name => 'a', version => 12, window => 'serta', key => 'quikset';

        }
        );
    $self->{storageengine}
        = Test::MockObject::Extends->new( $self->{storageengine} );

    $self->{storageengine}->mock(
        'fetch_transitional_state' => sub {
            'mockuuid', { META => 'data' }, 1, 2, 3, 4, 5;
        }
        )->mock(
        'revert',
        sub {
            shift;
            is +shift, $self->{idkey}, 'revert with idkey';
            is +shift, 'mockuuid', 'and with mock uuid';
        }
        )->mock(
        'store_new_canonical_state' => sub {
            shift;
            is +shift, $self->{idkey};
            is +shift, 'mockuuid';
            is +shift, $self->{delayedemitter};
            is_deeply [@_], [15];
        }
        );
    $self->{controlevents}->mock_expect_minimum_call_count( 'emit', 1,
        [ $self->{reducedmessage} ] );
    my $rule = Test::MockObject::Extends->new( bless {}, 'Rule' );
    $rule->mock(
        reduce => sub {
            shift;
            is +shift, $self->{delayedemitter}, 'reduce called with emitter';
            is_deeply [@_], [ 1, 2, 3, 4, 5 ], 'and expected data';
            15;
        }
    );
    my $reducer = Test::MockObject::Extends->new( $self->make_reducer );
    $reducer->mock(
        make_delayed_emitter => sub {
            isnt $self->{delayedemitter}, undef, 'delayed emitter defined';
            $self->{delayedemitter};
        }
        )->mock(
        rule => sub {
            shift;
            is +shift, $self->{idkey}, 'rule called with idkey';
            isnt $rule, undef, 'rule defined';
            $rule;
        }
        )->mock(
        make_reduced_message => sub {
            shift; isa_ok +shift, 'Replay::IdKey';
            isnt $self->{reducedmessage}, undef, 'reduced message defined';
            $self->{reducedmessage};
        }
        );
    is_deeply [], [ $reducer->execute_reduce( $self->{idkey} ) ];

    #    qr/dgo/, 'successful reduce';
    $self->{controlevents}->mock_tally;
}

__PACKAGE__->runtests;

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
