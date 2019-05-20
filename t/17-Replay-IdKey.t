use Test::Most tests => 2;
use Test::Exception;



use_ok 'Replay::IdKey';

#collection
is Replay::IdKey->new(name => 'a', version => '1')->collection(), 'replay-a1';
#from_full_spec
#parse_full_spec
#parse_cubby
#domain_rule_prefix
#window_prefix
#cubby
#full_spec
#rule_spec
#delivery
#summary
#globsummary
#marshall
#hash
#hash_list
