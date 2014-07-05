package Replay::StorageEngine::Mongo;

use Moose;
use MongoDB;
use MongoDB::OID;
use Data::UUID;
use Readonly;
use JSON;

Readonly my $REVERT_LOCK_TIMEOUT => 10;

extends 'Replay::BaseStorageEngine';

has mongo => (
    is      => 'ro',
    isa     => 'MongoDB::MongoClient',
    builder => '_build_mongo',
    lazy    => 1
);

has db => (is => 'ro', builder => '_build_db', lazy => 1);

has uuid => (is => 'ro', builder => '_build_uuid', lazy => 1);

my $store = {};

override retrieve => sub {
    my ($self, $idkey) = @_;
    super();
    return $self->document($idkey);
};

override absorb => sub {
    my ($self, $idkey, $atom, $meta) = @_;
    super();
    my $r = $self->collection($idkey)->update(
        { idkey => $idkey->cubby },
        {   '$push'     => { inbox => $atom },
            '$addToSet' => {
                windows      => $idkey->window,
                timeblocks      => { '$each' => $meta->{timeblocks} || [] },
                ruleversions => { '$each' => $meta->{ruleversions} || [] },
            },
            '$setOnInsert' => { idkey => { $idkey->hashList } }
        },
        { upsert => 1, multiple => 0 },
    );
    return $r;
};

sub revertThisRecord {
    my ($self, $idkey, $signature, $record) = @_;

    # reabsorb all of the desktop atoms into the record
    foreach my $atom (@{ $record->{'desktop'} || [] }) {
        $self->absorb($idkey, $atom);
    }

    # and unlock it
    my $unlockresult
        = $self->collection($idkey)
        ->update({ idkey => $idkey->cubby, locked => $signature } =>
            { '$unset' => { desktop => '', locked => '', lockExpireEpoch => '' } });
    die "UNABLE TO UNLOCK AFTER REVERT " unless $unlockresult->{n} == 1;
    return $unlockresult;
}

override checkout => sub {
    my ($self, $idkey, $timeout) = @_;
    my $uuid         = $self->generate_uuid;
    my $signature    = $self->stateSignature($idkey, [$uuid]);
    my $unlsignature = $self->stateSignature($idkey, [ $uuid, 'UNLOCKING' ]);

    # Lets try to get an expire lock, if it has timed out
    warn "Trying to unlock " . $idkey->cubby . " with $unlsignature";
    my $unlockresult = $self->collection($idkey)->find_and_modify(
        {   query => {
                idkey           => $idkey->cubby,
                locked          => { '$exists' => 1 },
                lockExpireEpoch => { '$lt' => time },
            },
            update => {
                '$set' => { locked => $unlsignature, lockExpireEpoch => time + $timeout, },
            },
            upsert => 0,
            new    => 1,
        }
    );

    # Oh my, we did. Well then, we should...
    $self->revertThisRecord($idkey, $unlsignature, $unlockresult)
        if ($unlockresult);

    # Now we try to get a read lock
    my $lockresult = $self->collection($idkey)->find_and_modify(
        {   query => {
                idkey   => $idkey->cubby,
                desktop => { '$exists' => 0 },
                '$or'   => [
                    { locked          => { '$exists' => 0 } },
                    { lockExpireEpoch => { '$lt'     => time } }
                ]
            },
            update => {
                '$set'    => { locked  => $signature, lockExpireEpoch => time + $timeout, },
                '$rename' => { 'inbox' => 'desktop' },
            },
            upsert => 0,
            new    => 1,
        }
    );

    # We didn't lock.  Return nothing.
    unless (defined $lockresult) {
        my $timeout
            = $self->collection($idkey)->find({ query => { idkey => $idkey->cubby } },
            { desktop => 1, locked => 1, lockExpireEpoch => 1 })
            || {};
        warn "UNABLE TO LOCK RECORD DESKTOP COUNT ("
            . scalar(@{ $timeout->{desktop} || [] })
            . ") RECORDS ARE LOCKED ("
            . ($timeout->{locked} || '')
            . ") FOR ("
            . (($timeout->{lockExpireEpoc} - time) || '')
            . ") MORE SECONDS";
        return;
    }

    #    my $cursor = $self->collection($idkey)->find(
    #      {  idkey => $idkey->cubby,
    #      , locked => $signature,  lockExpireEpoch => { '$gt' => time } }
    #    );

    # we must not affect the inbox on later updates!
    delete $lockresult->{inbox};

    # This takes care of sending the 'locked' event
    super();

    return $uuid, $lockresult;
};

override revert => sub {
    my ($self, $idkey, $uuid) = @_;
    my $signature = $self->stateSignature($idkey, [$uuid]);
    my $unlsignature = $self->stateSignature($idkey, [ $uuid, 'UNLOCKING' ]);
    my $state = $self->collection($idkey)->find_and_modify(
        {   query => {
                idkey   => $idkey->cubby,
                desktop => { '$exists' => 1 },
                locked  => $signature,
            },
            update => {
                '$set' => {
                    locked          => $unlsignature,
                    lockExpireEpoch => time + $REVERT_LOCK_TIMEOUT,
                },
            },
            upsert => 0,
            new    => 1,
        }
    );
    warn "tried to do a revert but didn't have a lock on it" unless $state;
    return unless $state;
    my $result = $self->revertThisRecord($idkey, $signature, $state);
    return $result->{ok};
};

override checkin => sub {
    my ($self, $idkey, $uuid, $state) = @_;
    my $signature = $self->stateSignature($idkey, [$uuid]);
    delete $state->{inbox};             # we must not affect the inbox on updates!
    delete $state->{desktop};           # there is no more desktop on checkin
    delete $state->{lockExpireEpoch};   # there is no more expire time on checkin
    delete $state->{locked};    # there is no more locked signature on checkin
    my $result = $self->collection($idkey)->find_and_modify(
        {   query  => { idkey => $idkey->cubby, locked => $signature },
            update => {
                '$set'   => $state,
                '$unset' => { desktop => '', lockExpireEpoch => '', locked => '' }
            },
            upsert => 0,
            new    => 1
        }
    );
    if ($result) {
        super();
    }
    return $result;    # no checkin
};

override windowAll => sub {
    my ($self, $idkey) = @_;
    return
        map { $_->{idkey}{key} => $_ }
        @{ $self->collection($idkey)
            ->find({ idkey => { '$regex' => '^' . $idkey->windowPrefix } })->all
            || [] };
};
#}}}}

sub _build_mongo {
    my ($self) = @_;
    return MongoDB::MongoClient->new();
}

sub _build_db {
    my ($self) = @_;
    my $config = $self->config;
    my $db     = $self->mongo->get_database($config->{stage} . '-replay');
    return $db;
}

sub _build_uuid {
    my ($self) = @_;
    return Data::UUID->new;
}

sub collection {
    my ($self, $idkey) = @_;
    my $name = $idkey->collection();
    return $self->db->get_collection($name);
}

sub document {
    my ($self, $idkey) = @_;
    return $self->collection($idkey)->find({ idkey => $idkey->cubby })->next
        || $self->new_document($idkey);
}

sub generate_uuid {
    my ($self) = @_;
    $self->uuid->to_string($self->uuid->create);
}

=head1 NAME

Replay::StorageEngine::Mongo - storage implimentation for mongodb

=head1 VERSION

Version 0.01

=head1 SYNOPSIS

This is the Storage engine implimentation for mongodb

Replay::StorageEngine::Mongo->new( ruleSoruce => $rs, eventSystem => $es, config => { Mongo => { host: ..., port: ... } } );

=head1 OVERRIDES

=head2 retrieve - get document

=head2 absorb - add atom

=head2 checkout - lock and return document

=head2 revert - revert and unlock document

=head2 checkin - update and unlock document

=head2 windowAll - get documents for a particular window

=head1 SUBROUTINES/METHODS

=head2 revertThisRecord

reversion implimentation

=head2 _build_mongo {

mongo builder/connector

=head2 _build_db {

get the object for the db client that indicates the db the document is in

=head2 _build_uuid {

make an object with which to generate uuids

=head2 collection {

get the object for the db client that indicates the collection this document is in

=head2 document {

return the document indicated by the idkey

=head2 generate_uuid {

create and return a new uuid

=head1 AUTHOR

David Ihnen, C<< <davidihnen at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-replay at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Replay>.  I will be notified, and then you'

        ll automatically be notified of progress on your bug as I make changes .

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

Copyright 2014 David Ihnen.

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


=head1 STORAGE ENGINE MODEL ASSUMPTIONS

IdKey: object that indicates all the axis of selection for the data requested
Atom: defined by the rule being processed; storage engine shouldn't care about it.

STATE DOCUMENT GENERAL TO STORAGE ENGINE

inbox: [ Array of Atoms ] - freshly arrived atoms are stored here.
canonical: [ Array of Atoms ] - the current reduced 
canonSignature: "SIGNATURE" - a sanity check to see if this canonical has been mucked with
timeblocks: [ Array of input timeblock names ]
ruleversions: [ Array of objects like { name: <rulename>, version: <ruleversion> } ]

STATE DOCUMENT SPECIFIC TO THIS IMPLIMENTATION

db is determined by idkey->ruleversion
collection is determined by idkey->collection
idkey is determined by idkey->cubby

desktop: [ Array of Atoms ] - the previously arrived atoms that are currently being processed
locked: "SIGNATURE" - if this is set, only a worker who knows the signature may update this
lockExpireEpoch: TIMEINT - used in case of processing timeout to unlock the record

STATE TRANSITIONS IN THIS IMPLEMENTATION 

checkout

rename inbox to desktop so that any new absorbs don't get confused with what is being processed

=head1 STORAGE ENGINE IMPLIMENTATION METHODS 

=head2 (state) = retrieve ( idkey )

Unconditionally return the entire state record 

=head2 (success) = absorb ( idkey, message, meta )

Insert a new atom into the indicated state

=head2 (uuid, state) = checkout ( idkey, timeout )

if the record is locked already
  if the lock is expired
    lock with a new uuid
      revert the state by reabsorbing the desktop to the inbox
      clear desktop
      clear lock
      clear expire time
  else 
    return nothing
else
  lock the record atomically so no other processes may lock it with a uuid
    move inbox to desktop
    return the uuid and the new state

=head2 revert  ( idkey, uuid )

if the record is locked with this uuid
  if the lock is not expired
    lock the record with a new uuid
      reabsorb the atoms in desktop
      clear desktop
      clear lock
      clear expire time
  else 
    return nothing, this isn't available for reverting
else 
  return nothing, this isn't available for reverting

=head2 checkin ( idkey, uuid, state )

if the record is locked, (expiration agnostic)
  update the record with the new state
  clear desktop
  clear lock
  clear expire time
else
  return nothing, we aren't allowed to do this

=cut

1;
