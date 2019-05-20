package Test::Replay::Role::StorageEngine;

use Replay::Signature;
use Replay::IdKey;
use Test::Most;
use Test::More tests => 3;

my $idkey = Replay::IdKey->new( name => 'a', version => 1 );

is $idkey->hash, $idkey->hash;

is Replay::Signature::switch( [ { yar => "woof" }, { woof => "yar" } ] ),
    Replay::Signature::switch( [ { woof => "yar" }, { yar => "woof" } ] );

is Replay::Signature::signature(
    $idkey, [ { yar => "woof" }, { woof => "yar" } ]
    ),
    Replay::Signature::signature( $idkey,
    [ { woof => "yar" }, { yar => "woof" } ] );

