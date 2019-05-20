package Replay::Signature;

use Storable qw/freeze/;
use Digest::MD5 qw/md5_hex/;
$Storable::canonical = 1;

sub signature {
    my ( $self, $idkey, $thing ) = @_;
    return unless defined $thing;
    my $sig = md5_hex( $idkey->hash . switch ($thing) );
    return $sig;
}

sub switch {
    my ($thing) = @_;
    if ( ref $thing eq 'ARRAY' ) {
        return list_signature($thing);
    }
    elsif ( ref $thing eq 'HASH' ) {
        return hash_signature($thing);
    }
    return scalar_signature($thing);
}

sub hash_signature {
    my $thing = shift;
    md5_hex(
        freeze( { map { ( $_, switch ( $thing->{$_} ) ) } keys %{$thing} } )
    );
}

sub list_signature {
    my $thing = shift;
    md5_hex( freeze( [ sort map { switch ($_) } @{$thing} ] ) );
}

sub scalar_signature {
    my $thing = shift;
    md5_hex( ref $thing ? freeze($thing) : $thing );
}

