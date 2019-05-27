package Replay::Role::MongoDB;

#all you need to get a Mongo up and running from blank unauthed
# - create a myUserAdmin
# use admin
# db.createUser( {
#       user: 'myUserAdmin',
#       pwd: 'abc123',
#       roles: [ { role: 'userAdminAnyDatabase', db: 'admin' } ] } )
# - enable user auth on the db and restart it (auth=true in mongodb.conf)
# - log in as that user
# mongo -u myUserAdmin -p abc123 admin
# - create the replay user
# db.createUser( { user: 'replayuser', pwd: 'replaypass', roles: [ { role:
# 'dbAdminAnyDatabase' ,db: 'admin' }, { role: 'readWriteAnyDatabase', db:
# 'admin' } ] } )

use Moose::Role;
use Carp qw/croak confess carp cluck/;
use Replay::StorageEngine::Lock;
use Data::Dumper;
use MongoDB;
use MongoDB::OID;
use JSON;
use Try::Tiny;
requires(
    qw(_build_mongo
        _build_db
        _build_dbname
        _build_dbauthdb
        _build_dbuser
        _build_dbpass
        new_document
        retrieve
        )
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

sub _build_mongo {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my ($self) = @_;
    my $db = MongoDB::MongoClient->new(
        db_name  => $self->dbauthdb,
        username => $self->dbuser,
        password => $self->dbpass
    );
    return $db;
}

sub assert_index {
    my ( $self, $idkey ) = @_;
    $self->collection($idkey)
        ->indexes->create_one( [ idkey => 1 ], { unique => 1 } );
}

sub checkout_record {
    my ( $self, $lock ) = @_;
    my $idkey = $lock->idkey;

    $self->assert_index($idkey);
    return $self->lock_cubby( lock => $lock, only_if_unlocked => 1 );
}

sub collection {
    my ( $self, $idkey ) = @_;
    confess 'WHAT IS THIS ' . $idkey if !ref $idkey;
    my $name = $idkey->collection();
    return $self->db->get_collection($name);
}

sub document {
    my ( $self, $idkey ) = @_;
    my $document
        = $self->collection($idkey)->find( { idkey => $idkey->cubby } )->next
        || $self->new_document($idkey);
    return $document;
}

sub current_lock {
    my ( $self, $idkey ) = @_;
    croak 'idkey for current_lock must be passed' if !$idkey;

    my $report
        = $self->db->get_collection( $idkey->collection )
        ->find_one( { idkey => $idkey->cubby },
        { locked => 1, lockExpireEpoch => 1, } );

    if ($report) {
        if ( $report->{locked} && $report->{lockExpireEpoch} ) {
            return Replay::StorageEngine::Lock->new(
                idkey           => $idkey,
                locked          => $report->{locked},
                lockExpireEpoch => $report->{lockExpireEpoch}
            );
        }
        else {
            return Replay::StorageEngine::Lock->empty( idkey => $idkey, );
        }
    }
    else {
        return Replay::StorageEngine::Lock->empty($idkey);
    }
}

# Mongo query: relock cubby document
sub lock_cubby {
    my ( $self, %args ) = @_;
    my $outlock = Replay::StorageEngine::Lock->empty( $args{lock}->idkey );
    my @onlyunlocked = (
        $args{only_if_unlocked}
        ? ( q^$or^ => [
                { locked => { q^$exists^ => 0 } },
                { locked => $args{lock}->locked }
            ]
            )
        : ()
    );

    # up front check to see if its already locked.
    # If it is, check to see if its expired.
    # If it is, try to relock it.
    my $current = $self->current_lock( $args{lock}->idkey );
    if ( $current->is_locked ) {
        if ( $current->is_expired ) {
            # locked, expired, attempt relock
            $outlock = $self->relock_expired( $args{lock}->idkey,
                $args{lock}->timeout );
        }
    }
    else {
        try {
            my $r = $self->collection( $args{lock}->idkey )->update_one(
                { idkey => $args{lock}->idkey->cubby, @onlyunlocked, },
                {   q^$set^ => {
                        locked          => $args{lock}->locked,
                        lockExpireEpoch => $args{lock}->lockExpireEpoch,
                    },
                    q^$setOnInsert^ =>
                        { IdKey => $args{lock}->idkey->marshall },
                },
                { upsert => 1, returnNewDocument => 1, },
            );
            if ( $r->modified_count + $r->matched_count > 0 || $r->upserted_id) {
                $outlock = $args{lock};
            }
        }
        catch {
            # Unhappy - Duplicate key errors mean the above query
            # didn't match so tried to insert but the unique constraint
            # was hit, meaning it was already checked out, but precheck
            # didn't see that.
            # Warn out about it.
            if ( $_->isa('MongoDB::DuplicateKeyError') ) {
                warn "Duplicate key despite precheck! "
                    . $args{lock}->idkey->full_spec;
            }
            else {
                croak $_;
            }
        }
    }
    return $outlock;
}

# Mongo query: relock desktop
sub relock_desktop {
    my ( $self, $lock ) = @_;
    my $ur = $self->BOXES->update_many(
        { idkey => $lock->idkey->full_spec },
        {   q^$set^ => {
                state  => 'desktop',        # reenforce state
                locked => $lock->locked,    # new lock
            },
        }
    );
    return $ur->modified_count;
}

sub relock_expired {
    my ( $self, $idkey, $timeout ) = @_;
    my $relock = Replay::StorageEngine::Lock->prospective( $idkey, $timeout );
    my $current = $self->current_lock($idkey);

    if ( !$current->is_expired ) {
        warn "Attempted to relock_expired an unexpired lock ("
            . ( time - $current->lockExpireEpoch )
            . ") seconds left";
        return Replay::StorageEngine::Lock->notlocked($idkey);
    }
    if ( $current->locked ) {
        warn "Attempt to relock_expired an expired locked key ("
            . ( $current->locked )
            . "), lock pending.";
    }
    else {
        warn "Attempt to relock_expired an unlocked key, lock pending.";
    }
    my $locked = $self->lock_cubby( lock => $relock, only_if_unlocked => 0 );
    if ( $locked > 0 ) {
        warn "Successfully relocked document ("
            . ($locked)
            . ").  Updating boxes.";
        my $desktop_count = $self->relock_desktop($relock);
        if ($desktop_count) {
            warn "Successfully relocked " . $desktop_count . " atoms.";
        }
        else {
            warn "zero desktop moved back to inbox!";
        }
    }
    else {
        warn "Failed to relock document!";
        return Replay::StorageEngine::Lock->notlocked($idkey);
    }
    return $relock;
}

sub count_inbox_outstanding {
    my ( $self, $idkey ) = @_;
    if ( defined &{ ref( $self->BOXES ) . '::count_documents' } ) {
        $self->BOXES->count_documents(
            { idkey => $idkey->full_spec, state => 'inbox' } );
    }
    else {
        $self->BOXES->count(
            { idkey => $idkey->full_spec, state => 'inbox' } );
    }
}

sub unlock_cubby {
    my ( $self, $lock ) = @_;

    my $unlock = $self->collection( $lock->idkey )->update_one(
        { idkey => $lock->idkey->cubby, locked => $lock->locked },
        { q^$unset^ => { locked => 1, lockExpireEpoch => 1, } },
    );

    return $unlock;
}

sub purge {
    my ( $self, $idkey) = @_;
    $self->collection( $idkey )
        ->delete_one(
        { idkey => $idkey->cubby, canonical => { q^$exists^ => 0 } } );
}

sub update_and_unlock {
    my ( $self, $lock, $state ) = @_;
    my @unsetcanon = ();
    my @setstate   = ();
    if ($state) {
        delete $state->{_id};
        delete $state->{lockExpireEpoch};
        delete $state->{locked};
        if ( @{ $state->{canonical} || [] } == 0 ) {
            delete $state->{canonical};
            @unsetcanon = ( canonical => 1 );
        }
        $self->clear_desktop($lock);
        @setstate = ( q^$set^ => $state );
    }
    my ( $package, $filename, $line ) = caller;
    my $newstate = $self->collection( $lock->idkey )->update_one(
        { idkey => $lock->idkey->cubby, locked => $lock->locked },
        {   @setstate,
            q^$unset^ => { lockExpireEpoch => 1, locked => 1, @unsetcanon }
        },
        { upsert => 0 }
    );
    return Replay::StorageEngine::Lock->empty($lock->idkey);
}

sub window_all {
    my ( $self, $idkey ) = @_;

    return {
        map { $_->{IdKey}->{key} => $_->{canonical} || [] }
            grep { defined $_->{IdKey}->{key} }
            $self->collection($idkey)->find(
            { idkey => { q^$regex^ => q(^) . $idkey->window_prefix } }
            )->all
    };
}

sub list_locked_keys {
    my ($self) = @_;
    my %keys = map { $_->{idkey} => $_ } (
        $self->BOXES->find( { locked => { q^$exists^ => 1 } },
            { idkey => 1 } )->all
    );
    my @idkeys
        = map { Replay::IdKey->from_full_spec( $_->{idkey} ) } values %keys;
    return @idkeys;
}

sub find_keys_need_reduce {
    my ($self) = @_;

    my @idkeys = map { Replay::IdKey->from_full_spec( $_->{idkey} ) }
        $self->BOXES->find( { state => 'inbox' }, { idkey => 1 } )->all;
    return @idkeys;
}

sub desktop_cursor {
    my ( $self, $lock ) = @_;
    $self->ensure_locked($lock);
    my $c = $self->BOXES->find(
        {   idkey  => $lock->idkey->full_spec,
            state  => 'desktop',
            locked => $lock->locked,
        }
    );
    return $c;
}

sub clear_desktop {
    my ( $self, $lock ) = @_;
    $self->ensure_locked($lock);
    my $r = $self->BOXES->delete_many(
        {   idkey  => $lock->idkey->full_spec,
            state  => 'desktop',
            locked => $lock->locked,
        }
    );
    return $r;
}

sub reabsorb {
    my ( $self, $lock, $empty ) = @_;
    $self->ensure_locked($lock);
    my $r = $self->BOXES->update_many(
        {   idkey  => $lock->idkey->full_spec,
            state  => 'desktop',
            locked => $lock->locked
        },
        { q^$set^ => { state => 'inbox' }, q^$unset^ => { locked => 1 } }
    );
    warn "Reabsorb executed, count modified: " . $r->modified_count
        unless $empty;
    return $r;
}

sub absorb {
    my ( $self, $idkey, $atom, $meta ) = @_;

    my $r = $self->BOXES->insert_one(
        {   idkey => $idkey->full_spec,
            meta  => $meta,
            atom  => $atom,
            state => 'inbox',
        }
    );
    return $r;
}

sub inbox_to_desktop {
    my ( $self, $lock ) = @_;

    return 0 unless $self->ensure_locked($lock);

    my $capacity = $self->ruleSource->by_idkey( $lock->idkey )->capacity();

    my @idsToProcess = map { $_->{'_id'} } $self->BOXES->find(
        {   idkey  => $lock->idkey->full_spec,
            state  => 'inbox',
            locked => { q^$exists^ => 0 }
        }
    )->fields( { _id => 1 } )->limit($capacity)->all;

    return $self->BOXES->update_many(
        {   idkey  => $lock->idkey->full_spec,
            state  => 'inbox',
            locked => { q^$exists^ => 0 },
            _id    => { q^$in^ => [@idsToProcess] }
        },
        { q^$set^ => { state => 'desktop', locked => $lock->locked, } }
    )->{modified_count};
}

sub BOXES {
    my ($self) = @_;
    my $boxes = $self->db->get_collection('BOXES');
    return $boxes;
}

1;

__END__

=pod

=head1 NAME

Replay::Role::MongoDB - Get Mongo up without duplication code

=head1 VERSION

Version 0.04

=head1 SYNOPSIS

 with qw(Replay::Role::MongoDB)

=head1 DESCRIPTION

Use this role to provide the shared implementation of mongo database access

=head1 SUBROUTINES/METHODS

requires (
    qw(_build_mongo
        _build_db
        _build_dbname
        _build_dbauthdb
        _build_dbuser
        _build_dbpass)
)

implements

=over 4

=head2 _build_mongo

build the mongo connection handle

=head2 checkout_record

given an IdKey, lock the document and return the uuid for the lock

=head2 collection

given an IdKey, return the collection it will be found in

=head2 document

given an IdKey, retrieve the document

=head2 current_lock

given an IdKey, return a lock object

=head2 relock

given an IdKey and a uuid, relock the record - presumably so that
the timeout doesn't expire

=head2 relock_expired

given an IdKey to a lock with an expired record, take over the lock

=head2 revert_this_record

given an idkey to a locked record and its uuid key, revert this to its
unchecked out, unchanged state

=head2 update_and_unlock

given an idkey to a locked record and its uuid key and a new
canonical state, update canonical state clear desktop and unlock

=head1 AUTHOR

John Scoles, C<< <byterock  at hotmail.com> >>

=head1 CONFIGURATION AND ENVIRONMENT

Implied by context

=head1 DIAGNOSTICS

nothing to say here

=head1 DEPENDENCIES

Nothing outside the normal Replay world

=head1 INCOMPATIBILITIES

Nothing to report

=head1 BUGS AND LIMITATIONS

Please report any bugs or feature requests to C<bug-replay at rt.cpan.org>,
or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Replay>.  I will be
notified, and then you'll automatically be notified of progress on your
bug as I make changes .

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


=head1 ACKNOWLEDGMENTS


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
AND CONTRIBUTORS 'AS IS' AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES.
THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE, OR NON-INFRINGEMENT ARE DISCLAIMED TO THE EXTENT PERMITTED BY
YOUR LOCAL LAW. UNLESS REQUIRED BY LAW, NO COPYRIGHT HOLDER OR
CONTRIBUTOR WILL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, OR
CONSEQUENTIAL DAMAGES ARISING IN ANY WAY OUT OF THE USE OF THE PACKAGE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut

1;
