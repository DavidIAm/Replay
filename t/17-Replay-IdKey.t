use Test::Most tests => 28;

use Test::Exception;

use_ok 'Replay::IdKey';

#collection
is Replay::IdKey->new( name => 'a', version => '1' )->collection(),
    'replay-a1', 'collection name mapping';

#parse_full_spec no revision no domain
is_deeply {
    Replay::IdKey->parse_full_spec(
        'domain-null-name-b-version-1-wind-c-key-d-revision-null')
}, { name => 'b', version => '1', window => 'c', key => 'd' },
    'spec no domain no revision';

#from_full_spec
ok Replay::IdKey->from_full_spec(
    'domain-null-name-b-version-1-wind-c-key-d-revision-null')
    ->isa('Replay::IdKey'), "makes an idkey";

#parse_cubby
is_deeply { Replay::IdKey->parse_cubby('wind-c-key-d') },
    { window => 'c', key => 'd' }, 'cubby parse';

my $testkey = Replay::IdKey->from_full_spec(
    'domain-a-name-b-version-1-wind-c-key-d-revision-2');
my $nodomaintest = Replay::IdKey->from_full_spec(
    'domain-null-name-b-version-1-wind-c-key-d-revision-2');
my $norevisiontest = Replay::IdKey->from_full_spec(
    'domain-a-name-b-version-1-wind-c-key-d-revision-null');
my $neithertest = Replay::IdKey->from_full_spec(
    'domain-null-name-b-version-1-wind-c-key-d-revision-null');

#domain_rule_prefix
is $testkey->domain_rule_prefix(), 'domain-a-name-b-version-1',
    'domain rule prefix';

#window_prefix
is $testkey->window_prefix(), 'wind-c-key-', 'window prefix';

#cubby
is $testkey->cubby(), 'wind-c-key-d', 'cubby name';

#full_spec
is $testkey->full_spec(),
    'domain-a-name-b-version-1-wind-c-key-d-revision-2', 'cubby name';
is $nodomaintest->full_spec(),
    'domain-null-name-b-version-1-wind-c-key-d-revision-2', 'cubby name';
is $norevisiontest->full_spec(),
    'domain-a-name-b-version-1-wind-c-key-d-revision-null', 'cubby name';
is $neithertest->full_spec(),
    'domain-null-name-b-version-1-wind-c-key-d-revision-null', 'cubby name';

#rule_spec
is $testkey->rule_spec(), 'name-b-version-1', 'rule spec output';

#delivery
is Replay::IdKey->new( name => 'a', version => 1 )->delivery->full_spec,
    'domain-null-name-a-version-1-wind-null-key-null-revision-null',
    'delivery minimal';
is Replay::IdKey->new( name => 'a', version => 1, window => 'b' )->delivery()
    ->full_spec, 'domain-null-name-a-version-1-wind-b-key-null-revision-null',
    'delivery window';
is Replay::IdKey->new(
    name    => 'a',
    version => 1,
    window  => 'b',
    key     => 'c'
    )->delivery->full_spec,
    'domain-null-name-a-version-1-wind-b-key-c-revision-null', 'delivery key';
is Replay::IdKey->new(
    name     => 'a',
    version  => 1,
    window   => 'b',
    key      => 'c',
    revision => 2
    )->delivery->full_spec,
    'domain-null-name-a-version-1-wind-b-key-c-revision-2',
    'delivery revision';

#summary
is Replay::IdKey->new( name => 'a', version => 1 )->delivery->full_spec,
    'domain-null-name-a-version-1-wind-null-key-null-revision-null',
    'summary minimal';
is Replay::IdKey->new( name => 'a', version => 1, window => 'b' )->summary()
    ->full_spec, 'domain-null-name-a-version-1-wind-b-key-null-revision-null',
    'summary window';
is Replay::IdKey->new(
    name    => 'a',
    version => 1,
    window  => 'b',
    key     => 'c'
    )->summary->full_spec,
    'domain-null-name-a-version-1-wind-b-key-null-revision-null',
    'summary key';
is Replay::IdKey->new(
    name     => 'a',
    version  => 1,
    window   => 'b',
    key      => 'c',
    revision => 2
    )->summary->full_spec,
    'domain-null-name-a-version-1-wind-b-key-null-revision-2',
    'summary revision';

#globsummary
is Replay::IdKey->new( name => 'a', version => 1 )->delivery->full_spec,
    'domain-null-name-a-version-1-wind-null-key-null-revision-null',
    'globsummary minimal';
is Replay::IdKey->new( name => 'a', version => 1, window => 'b' )
    ->globsummary()->full_spec,
    'domain-null-name-a-version-1-wind-null-key-null-revision-null',
    'globsummary window';
is Replay::IdKey->new(
    name    => 'a',
    version => 1,
    window  => 'b',
    key     => 'c'
    )->globsummary->full_spec,
    'domain-null-name-a-version-1-wind-null-key-null-revision-null',
    'globsummary key';
is Replay::IdKey->new(
    name     => 'a',
    version  => 1,
    window   => 'b',
    key      => 'c',
    revision => 2
    )->globsummary->full_spec,
    'domain-null-name-a-version-1-wind-null-key-null-revision-2',
    'globsummary revision';

#hash_list
is_deeply { $testkey->hash_list }, { name => 'b', version => 1, window => 'c', key => 'd', revision => 2  }, 'hash_list';

#hash
is length $testkey->hash, 32, 'hash';

#marshall
is_deeply $testkey->marshall, { name => 'b', version => 1, window => 'c', key => 'd', revision => 2  }, 'hash_list';

