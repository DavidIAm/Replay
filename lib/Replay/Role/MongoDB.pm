package Replay::Role::MongoDB;

#all you need to get a Mogo up and running

use Moose::Role;
use Carp qw/croak confess carp/;
use JSON;
requires(
    qw(_build_mongo
      _build_db
      _build_dbname
      _build_dbauthdb
      _build_dbuser
      _build_dbpass)
);

our $VERSION = q(0.01);

has db       => ( is => 'ro', builder => '_build_db',       lazy => 1, );
has dbname   => ( is => 'ro', builder => '_build_dbname',   lazy => 1, );
has dbauthdb => ( is => 'ro', builder => '_build_dbauthdb', lazy => 1, );
has dbuser   => ( is => 'ro', builder => '_build_dbuser',   lazy => 1, );
has dbpass   => ( is => 'ro', builder => '_build_dbpass',   lazy => 1, );

has mongo => (
    is      => 'ro',
    isa     => 'MongoDB::MongoClient',
    builder => '_build_mongo',
    lazy    => 1,
);

sub checkout_record {
    my ( $self, $idkey, $signature, $timeout ) = @_;

    # try to get lock
    my $lockresult = $self->collection($idkey)->find_and_modify(
        {
            query => {
                idkey   => $idkey->cubby,
                desktop => { q^$^ . 'exists' => 0 },
                q^$^
                  . 'or' => [
                    { locked => { q^$^ . 'exists' => 0 } },
                    {
                        q^$^
                          . 'and' => [
                            { locked => $signature },
                            {
                                q^$^
                                  . 'or' => [
                                    {
                                        lockExpireEpoch =>
                                          { q^$^ . 'gt' => time }
                                    },
                                    {
                                        lockExpireEpoch =>
                                          { q^$^ . 'exists' => 0 }
                                    }
                                  ]
                            }
                          ]
                    }
                  ]
            },
            update => {
                q^$^
                  . 'set' =>
                  { locked => $signature, lockExpireEpoch => time + $timeout, },
                q^$^ . 'rename' => { 'inbox' => 'desktop' },
            },
            upsert => 0,
            new    => 1,
        }
    );

    return $lockresult;
}

sub collection {
    my ( $self, $idkey ) = @_;
    use Carp qw/confess/;
    confess "WHAT IS THIS $idkey " unless ref $idkey;
    my $name = $idkey->collection();
    return $self->db->get_collection($name);
}

sub document {
    my ( $self, $idkey ) = @_;
    return $self->collection($idkey)->find( { idkey => $idkey->cubby } )->next
      || $self->new_document($idkey);
}

sub generate_uuid {
    my ($self) = @_;
    return $self->uuid->to_string( $self->uuid->create );
}

sub lockreport {
    my ( $self, $idkey ) = @_;
    return [
        $self->collection($idkey)->find( { idkey => $idkey->cubby },
            { locked => JSON::true, lockExpireEpoch => JSON::true } )->all
    ];
}

sub relock {
    my ( $self, $idkey, $current_signature, $new_signature, $timeout ) = @_;

    # Lets try to get an expire lock, if it has timed out
    my $unlockresult = $self->collection($idkey)->find_and_modify(
        {
            query  => { idkey => $idkey->cubby, locked => $current_signature },
            update => {
                q^$^
                  . 'set' => {
                    locked          => $new_signature,
                    lockExpireEpoch => time + $timeout,
                  },
            },
            upsert => 0,
            new    => 1,
        }
    );

    return $unlockresult;
}

sub relock_expired {
    my ( $self, $idkey, $signature, $timeout ) = @_;

    # Lets try to get an expire lock, if it has timed out
    my $unlockresult = $self->collection($idkey)->find_and_modify(
        {
            query => {
                idkey  => $idkey->cubby,
                locked => { q^$^ . 'exists' => 1 },
                q^$^
                  . 'or' => [
                    { lockExpireEpoch => { q^$^ . 'lt'     => time } },
                    { lockExpireEpoch => { q^$^ . 'exists' => 0 } }
                  ]
            },
            update => {
                    q^$^
                  . 'set' =>
                  { locked => $signature, lockExpireEpoch => time + $timeout, },
            },
            upsert => 0,
            new    => 1,
        }
    );

    return $unlockresult;
}

sub relock_i_match_with {
    my ( $self, $idkey, $oldsignature, $newsignature ) = @_;
    my $unluuid      = $self->generate_uuid;
    my $unlsignature = $self->state_signature( $idkey, [$unluuid] );
    my $state        = $self->collection($idkey)->find_and_modify(
        {
            query  => { idkey => $idkey->cubby, locked => $oldsignature, },
            update => {
                q^$^
                  . 'set' => {
                    locked          => $unlsignature,
                    lockExpireEpoch => time + $self->timeout,
                  },
            },
            upsert => 0,
            new    => 1,
        }
    );
    carp q(tried to do a revert but didn't have a lock on it) if not $state;
    $self->eventSystem->control->emit(
        MessageType => 'NoLockDuringRevert',
        $idkey->hash_list,
    );
    return if not $state;
    $self->revert_this_record( $idkey, $unlsignature, $state );
    my $result = $self->unlock( $idkey, $unluuid, $state );
    return defined $result;
}

sub revert_this_record {
    my ( $self, $idkey, $signature, $document ) = @_;

    croak
"This document isn't locked with this signature ($document->{locked},$signature)"
      if $document->{locked} ne $signature;

    # reabsorb all of the desktop atoms into the document
    foreach my $atom ( @{ $document->{'desktop'} || [] } ) {
        $self->absorb( $idkey, $atom );
    }

    # and clear the desktop state
    my $unlockresult =
      $self->collection($idkey)
      ->update( { idkey => $idkey->cubby, locked => $signature } =>
          { q^$^ . 'unset' => { desktop => 1 } } );
    croak q(UNABLE TO RESET DESKTOP AFTER REVERT ) if $unlockresult->{n} == 0;
    return $unlockresult;
}

sub update_and_unlock {
    my ( $self, $idkey, $uuid, $state ) = @_;
    my $signature = $self->state_signature( $idkey, [$uuid] );
    my @unsetcanon = ();
    if ($state) {
        delete $state->{_id};         # cannot set _id!
        delete $state->{inbox};       # we must not affect the inbox on updates!
        delete $state->{desktop};     # there is no more desktop on checkin
        delete
          $state->{lockExpireEpoch};  # there is no more expire time on checkin
        delete $state->{locked};  # there is no more locked signature on checkin
        if ( @{ $state->{canonical} || [] } == 0 ) {
            delete $state->{canonical};
            @unsetcanon = ( canonical => 1 );
        }
    }
    return $self->collection($idkey)->find_and_modify(
        {
            query  => { idkey => $idkey->cubby, locked => $signature },
            update => {
                ( $state ? ( q^$^ . 'set' => $state ) : () ),
                q^$^
                  . 'unset' => {
                    desktop         => 1,
                    lockExpireEpoch => 1,
                    locked          => 1,
                    @unsetcanon
                  }
            },
            upsert => 0,
            new    => 1
        }
    );
}

1;

=pod

=head1 NAME

Replay::Role::MongoDBt - Get Mongo up wituout duplication code

=head1 VERSION

Version 0.01

=head1 SYNOPSIS

=head1 DESCRIPTION

Each

=head1 SUBROUTINES/METHODS


=head1 AUTHOR

John Scoles, C<< <byterock  at hotmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-replay at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Replay>.  I will be notified, and then you'll automatically be notified of progress on your bug as I make changes .

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Replay


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Replay>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Replay>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Replay>

=item * Search CPAN

L<http://search.cpan.org/dist/Replay/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2015 John Scoles.

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). You may obtain a
copy of the full license at:

L<http://www.perlfoundation.org/artistic_license_2_0>

Any use, modification, and distribution of the Standard or Modified
Versions is governed by this Artistic License. By using, modifying or
distributing the Package, you accept this license. Do not use, modify,
or distribute the Package, if you do not accept this license.

If your Modified Version has been derived from a Modified Version made
by someone other than you, you are nevertheless required to ensure that
your Modified Version complies with the requirements of this license.

This license does not grant you the right to use any trademark, service
mark, tradename, or logo of the Copyright Holder.

This license includes the non-exclusive, worldwide, free-of-charge
patent license to make, have made, use, offer to sell, sell, import and
otherwise transfer the Package with respect to any patent claims
licensable by the Copyright Holder that are necessarily infringed by the
Package. If you institute patent litigation (including a cross-claim or
counterclaim) against any party alleging that the Package constitutes
direct or contributory patent infringement, then this Artistic License
to you shall terminate on the date that such litigation is filed.

Disclaimer of Warranty: THE PACKAGE IS PROVIDED BY THE COPYRIGHT HOLDER
AND CONTRIBUTORS "AS IS' AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES.
THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE, OR NON-INFRINGEMENT ARE DISCLAIMED TO THE EXTENT PERMITTED BY
YOUR LOCAL LAW. UNLESS REQUIRED BY LAW, NO COPYRIGHT HOLDER OR
CONTRIBUTOR WILL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, OR
CONSEQUENTIAL DAMAGES ARISING IN ANY WAY OUT OF THE USE OF THE PACKAGE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut

1;
