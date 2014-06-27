package Replay::StorageEngine::Mongo;

use Moose;
use MongoDB;
use MongoDB::OID;
use Data::UUID;

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

=head1 STORAGE ENGINE MODEL ASSUMPTIONS

IdKey: object that indicates all the axis of selection for the data requested
Atom: defined by the rule being processed; storage engine shouldn't care about it.

STATE DOCUMENT GENERAL TO STORAGE ENGINE

inbox: [ Array of Atoms ] - freshly arrived atoms are stored here.
canonical: [ Array of Atoms ] - the current reduced 
canonSignature: "SIGNATURE" - a sanity check to see if this canonical has been mucked with

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

=over 4

=item (state) = retrieve ( idkey )

Unconditionally return the entire state record 

=item (success) = absorb ( idkey, message )

Insert a new atom into the indicated state

=item (uuid, state) = checkout ( idkey, timeout )

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

=item revert  ( idkey, uuid )

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

=item checkin ( idkey, uuid, state )

if the record is locked, (expiration agnostic)
  update the record with the new state
  clear desktop
  clear lock
  clear expire time
else
  return nothing, we aren't allowed to do this

=cut

override retrieve => sub {
    my ($self, $idkey) = @_;
    super();
    return $self->document($idkey);
};

override absorb => sub {
    my ($self, $idkey, $atom) = @_;
    super();
    my $r = $self->collection($idkey)->update(
        { idkey   => $idkey->cubby },
        { '$push' => { inbox => $atom } },
        { upsert  => 1, multiple => 0 }
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
    die "UNABLE TO UNLOCK AFTER REVERT" unless $unlockresult->{n} == 1;
    return $unlockresult;
}

override checkout => sub {
    my ($self, $idkey, $timeout) = @_;
    super();
    my $uuid         = $self->generate_uuid;
    my $signature    = $self->stateSignature($idkey, [$uuid]);
    my $unlsignature = $self->stateSignature($idkey, [ $uuid, 'UNLOCKING' ]);

    # Lets try to get an expire lock, if it has timed out
    my $unlockresult = $self->collection($idkey)->find_and_modify(
        {   query => {
                idkey           => $idkey->cubby,
                desktop         => { '$exists' => 0 },
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
    return unless (defined $lockresult);

    #    my $cursor = $self->collection($idkey)->find(
    #      {  idkey => $idkey->cubby,
    #      , locked => $signature,  lockExpireEpoch => { '$gt' => time } }
    #    );

    delete $lockresult->{value}->{inbox}
        ;    # we must not affect the inbox on later updates!
    return $uuid, $lockresult;
};

override revert => sub {
    my ($self, $idkey, $uuid) = @_;
    my $signature = $self->stateSignature($idkey, [$uuid]);
    my $unlsignature = $self->stateSignature($idkey, [ $uuid, 'UNLOCKING' ]);
    my $state = $self->collection($idkey)->find_and_modify(
        {   query => {
                idkey           => $idkey->cubby,
                desktop         => { '$exists' => 1 },
                locked          => $signature,
                lockExpireEpoch => { '$gt' => time },
            },
            update => {
                '$set' => { locked => $unlsignature, lockExpireEpoch => time + $timeout, },
            },
            upsert => 0,
            new    => 1,
        }
    );
    warn "tried to do a revert but didn't have a lock on it" unless $state;
    return unless $state;
    my $result = $self->revertThisRecord($idkey, $signature, $result);
    return $result->{ok};
};

override checkin => sub {
    my ($self, $idkey, $uuid, $state) = @_;
    my $signature = $self->stateSignature($idkey, [$uuid]);
    delete $state->{inbox};             # we must not affect the inbox on updates!
    delete $state->{desktop};           # there is no more desktop on checkin
    delete $state->{lockExpireEpoch};   # there is no more expire time on checkin
    delete $state->{locked};    # there is no more locked signature on checkin
    super();
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
    return $result;
};

override windowAll => sub {
    my ($self, $idkey) = @_;
    return $self->collection($idkey)
        ->find({ idkey => { '$regex' => '^' . $idkey->windowPrefix } })->all;
};

sub _build_mongo {
    my ($self) = @_;
    return MongoDB::MongoClient->new();
}

sub _build_db {
    my ($self) = @_;
    my $config = $self->locale->config;
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
    return $self->collection($idkey)->find({ idkey => $idkey->cubby })->next;
}

sub generate_uuid {
    my ($self) = @_;
    $self->uuid->to_string($self->uuid->create);
}

1;
