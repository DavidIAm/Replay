package Replay::Role::StorageEngine;

use Moose::Role;
requires qw(absorb retrieve find_keys_need_reduce find_keys_active_checkout
    ensure_locked window_all checkin desktop_cursor clear_desktop
    reabsorb inbox_to_desktop relock_expired list_locked_keys
    just_unlock purge expire_all_locks );
use Digest::MD5 qw/md5_hex/;
use feature 'current_sub';
use Data::Dumper;
use Data::UUID;
use Replay::Message::Fetched;
use Replay::StorageEngine::Lock;
use Replay::Message::FoundKeysForReduce;
use Replay::Signature;
use Replay::Message::Locked;
use Set::Scalar;
use Set::Object;
use Replay::Message::NewCanonical;
use Replay::Message::NoLock::DuringRevert;
use Replay::Message::NoLock;
use Replay::Message::NoLock::PostRevert;
use Replay::Message::NoLock::PostRevertRelock;
use Replay::Message::Reducable;
use Replay::Message::Reducing;
use Replay::Message::Reverted;
use Replay::Message::Unlocked;
use Replay::Message::WindowAll;
use Replay::IdKey;
use Storable qw/freeze/;
use Try::Tiny;
use Readonly;
use AnyEvent;

use Carp qw/croak carp/;

our $VERSION = '0.02';

Readonly my $REDUCE_TIMEOUT => 60;

$Storable::canonical = 1;    ## no critic (ProhibitPackageVars)

Readonly my $READONLY => 1;

has config => ( is => 'ro', isa => 'HashRef[Item]', required => 1 );

has ruleSource => ( is => 'ro', isa => 'Replay::RuleSource', required => 1 );

has eventSystem =>
    ( is => 'ro', isa => 'Replay::EventSystem', required => 1 );

has uuid => ( is => 'ro', builder => '_build_uuid', lazy => 1 );

has timeout => ( is => 'ro', default => 20, );

sub fetch_transitional_state {
    my ( $self, $idkey ) = @_;

    my ($lock) = $self->checkout( $idkey, $REDUCE_TIMEOUT );

    if ( !$lock->is_locked ) {
        return;
    }

    my $cursor = $self->desktop_cursor($lock);
    if ( !$cursor->has_next ) {
        $self->revert($lock);
        return;
    }

    my $cubby = $self->retrieve($idkey);

    # merge in canonical, moving atoms from desktop
    my ( $mergedmeta, @state );
    try {
        ( $mergedmeta, @state ) = $self->merge(
            $idkey,
            $cursor->all,
            map {
                {   idkey => ( $idkey->cubby || q^^ ),
                    meta => {
                        Domain       => ( $cubby->{Domain}       || [] ),
                        Timeblocks   => ( $cubby->{Timeblocks}   || [] ),
                        Ruleversions => ( $cubby->{Ruleversions} || [] ),
                    },
                    atom => $_,
                }
            } @{ $cubby->{canonical} || [] }
        );
    }
    catch {
        carp 'Reverting because doing the merge caused an exception ' . $_
            . "\n";
        $self->revert($lock);
        return;
    };

    # New document special case.  Awkward!
    $mergedmeta->{Timeblocks}   ||= [];
    $mergedmeta->{Domain}       ||= [];
    $mergedmeta->{Ruleversions} ||= [];

    # notify interested parties
    $self->eventSystem->control->emit(
        Replay::Message::Reducing->new( $idkey->marshall ) );

    # return uuid and list
    return $lock => $mergedmeta => @state;
}

sub merge {
    my ( $self, $idkey, @list ) = @_;
    my $meta = {};
    foreach my $k (
        Set::Object->new( map { keys %{ $_->{meta} } } @list )->members )
    {
        $meta->{$k}
            = Set::Object->new( map { $_->{meta}->{$k} } @list )->members,;
    }

    # for each rule involved
    foreach (
        Set::Scalar->new( map { $_->{rule} } @{ $meta->{Ruleversions} } )
        ->members )
    {
        if (scalar Set::Scalar->new(
                map { $_->{version} } @{ $meta->{Ruleversions} }
            )->size > 1
            )
        {
            croak 'data model integrity error! '
                . 'More than one version of the same rule reffed!';
        }
    }
    return $meta,
        sort { $self->rule($idkey)->compare( $a, $b ) }
        map { $_->{atom} } @list;
}

sub fetch_canonical_state {
    my ( $self, $idkey ) = @_;

    my $cubby = $self->retrieve($idkey);

    my $e
        = $self->state_signature( $idkey, $cubby->{canonical} || [] ) || q();
    if ( ( $cubby->{canonSignature} || q() ) ne ( $e || q() ) ) {
        carp q^canon signature didn't match. Don't worry about it.^;
    }

    return @{ $cubby->{canonical} || [] };
}

sub store_new_canonical_state {
    my ( $self, $lock, $emitter, @atoms ) = @_;
    my $idkey = $lock->idkey;
    my $cubby = $self->retrieve($idkey);
    $cubby->{canonVersion}++;
    $cubby->{canonical} = [@atoms];
    $cubby->{canonSignature}
        = $self->state_signature( $idkey, $cubby->{canonical} );
    my $newstate = $self->checkin( $lock, $cubby );
    $emitter->release;

    foreach my $atom ( @{ $emitter->atomsToDefer } ) {
        carp 'ABSORB DEFERRED ATOM';
        $self->absorb( $idkey, $atom, {} );
    }
    my $new_conical_msg
        = Replay::Message::NewCanonical->new( $idkey->marshall );
    $self->eventSystem->report->emit($new_conical_msg);
    $self->eventSystem->control->emit($new_conical_msg);
    $self->emit_reducable_if_needed($idkey);
    return $newstate;    # release pending messages
}

# accessor - how to get the rule for an idkey
sub rule {
    my ( $self, $idkey ) = @_;
    my $rule = $self->ruleSource->by_idkey($idkey);
    if ( not defined $rule ) {
        croak 'No such rule ' . $idkey->rule_spec;
    }
    return $rule;
}

# merge a list of atoms with the existing list in that slot
sub expired_lock_recover {
    my ( $self, $idkey, $timeout ) = @_;

    my $relock = Replay::StorageEngine::Lock->prospective( $idkey, $timeout );
    my $expire_relock = $self->relock_expired($relock);

    if ( $expire_relock->matches($relock) && $expire_relock->is_locked() ) {
        $self->revert_this_record($expire_relock);
        $self->eventSystem->control->emit(
            Replay::Message::NoLock::PostRevert->new( $idkey->marshall ),
        );
    }
    else {
        carp 'Unable to relock expired! ' . $idkey->cubby . qq(\n);
        return;
    }
    return ($expire_relock);
}

sub emit_lock_error {
    my ( $self, $lock ) = @_;
    carp q(Unable to obtain lock because the current )
        . q(one is locked and unexpired ())
        . $lock->idkey->cubby
        . qq(\)\n);
    $self->eventSystem->control->emit(
        Replay::Message::NoLock->new( $lock->idkey->marshall ),
    );
    return;
}

# Locking states
# 1. unlocked ( lock does not exist )
# 2. locked unexpired ( lock set to a signature, lockExpired epoch in future )
# 3. locked expired ( lock est to a signature, lockExpired epoch in past )
# checkout allowed when in states (1) and sometimes (2) when we supply the
# signature it is currently locked with
# if is in state 2 and we don't have the signature, lock is unavailable
# if it is in state 3, we lock it with a temporary signature as an expired
# lock, revert its desktop to the inbox, then try to relock it with a new
# signature  If it relocks we are in state-2-with-signature and are able to
# check it out
sub checkout {
    my ( $self, $idkey, $timeout ) = @_;
    $timeout ||= $self->timeout;
    my $prelock
        = Replay::StorageEngine::Lock->prospective( $idkey, $timeout );

    my $lock = $self->checkout_record($prelock);

    if ( !$lock->is_locked ) {
        return $lock;
    }

    if ( $self->ensure_locked($lock) ) {
        $self->inbox_to_desktop($lock);
        $self->emit_reducable_if_needed( $lock->idkey );
        return $lock;
    }

    if ( $lock->is_expired ) {
        ($lock) = $self->expired_lock_recover( $lock->idkey, $timeout );
    }

    if ( $lock->is_locked ) {
        return $self->checkout_record( $lock, $timeout );
    }
    else {
        $self->emit_lock_error($lock);
    }

    carp q(checkout after revert and relock failed. )
        . q(Mangled state in COLLECTION \()
        . $lock->idkey->collection
        . q(\) IDKEY \()
        . $lock->idkey->cubby . q(\));

    my $empty_lock = Replay::StorageEngine::Lock->empty( $lock->idkey );
    return $empty_lock;
}

before 'checkin' => sub {
    my ( $self, $lock, $cubby ) = @_;

    #     carp('Replay::BaseStorageEnginee  before checkin');
    my $unlock_msg = Replay::Message::Unlocked->new( $lock->idkey->marshall );
    return $self->eventSystem->control->emit($unlock_msg);
};

before 'retrieve' => sub {
    my ( $self, $idkey ) = @_;

    confess 'idkey cannot be null' if !defined $idkey;

    #    carp('Replay::BaseStorageEnginee  before retrieve');
    my $fetch_msg = Replay::Message::Fetched->new( $idkey->marshall );
    return $self->eventSystem->control->emit($fetch_msg);
};

after 'absorb' => sub {
    my ( $self, $idkey ) = @_;

  #       carp('Replay::BaseStorageEnginee  after absorb '.$self.', .'$idkey);
    my $reduce_msg = Replay::Message::Reducable->new( $idkey->marshall );
    return $self->eventSystem->reduce->emit($reduce_msg);
};

sub revert {
    my ( $self, $lock ) = @_;
    $self->revert_this_record($lock);
    my $revert_msg = Replay::Message::Reverted->new( $lock->idkey->marshall );
    $self->eventSystem->control->emit($revert_msg);
    $self->emit_reducable_if_needed( $lock->idkey );

    #hey Dave what is the line above for will never get to it???
}

# accessor - given a state, generate a signature
sub state_signature {
    my ( $self, $idkey, $list ) = @_;
    return Replay::Signature::signature( $idkey, $list );
}

sub emit_reducable_if_needed {
    my ( $self, $idkey ) = @_;
    if ( $self->has_inbox_outstanding($idkey) )
    {    # renotify reducer if inbox currently has entries
        my $reduce_msg = Replay::Message::Reducable->new( $idkey->marshall );
        $self->eventSystem->reduce->emit($reduce_msg);
    }
}

sub new_document {
    my ( $self, $idkey ) = @_;

    return {
        idkey        => { $idkey->hash_list },
        Windows      => [],
        Timeblocks   => [],
        Ruleversions => [],
    };
}

sub revert_all_expired_locks {
    my ($self) = @_;
    foreach my $lock ( grep { $_->is_locked }
        map { $self->expired_lock_recover($_) } $self->list_locked_keys() )
    {
        $self->revert($lock);
    }
}

sub _build_uuid {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my ($self) = @_;
    my $uuid = Data::UUID->new;
    return $uuid;
}

1;

__END__

=pod

=head1 NAME

Replay::Role::StorageEngine - wrappers for the storage engine implementation

=head1 VERSION

Version 0.01

=head1 SYNOPSIS

    IMPLEMENTATIONCLASS->new(
        config      => $self->config,
        ruleSource  => $self->ruleSource,
        eventSystem => $self->eventSystem,
    );

=head1 DESCRIPTION

This is the role definition for the storage engine implementation 
specific parts of the Replay system.

=head1 SUBROUTINES/METHODS

These methods are called by the StorageEngine interface that this Role
helps engines to fulfill

=head2 success = absorb(idkey, atom, meta)

accept a new atom at a location idkey with metadata attached.  no locking.
used by Mapper code

=head2 statelist = fetch_canonical_state(idkey)

access to the current canonical state.  no locking. used by reporting code.

=head2 lock, metadata, statelist = fetch_transitional_state(idkey)

check out a state for transition.  retain the lock value to use later.

automatically reverts previous checkout if lock is expired

Used by Reducer code

=head2 success = store_new_canonical_state(lock, emitter, @atoms)

lock is the lock returned from the fetch_transitional_state function

emitter is a Replay::DelayedEmitter object. It categorizes the complex 
types of output that a reducer may have produced 

atoms are what the new canonical state consists of.

check in a state for transition if uuid matches.  unlocks record if success.

Used by Reducer code

=head1 DATA TYPES

 types: Replay::IdKey
 - atom
  { a hashref which is an element of the state for this rule }
 - signature: md5 sum 

 interface:
  - boolean absorb(idkey, atom): accept a new atom into a state
  - state fetch_transitional_state(idkey): returns a new key-state for reduce processing
  - boolean store_new_canonical_state(idkey, uuid, emitter, atoms): accept a new canonical state
  - state fetch_canonical_state(idkey): returns the current collective state

 events emitted:
  - Replay::Message::Fetched - when a canonical state is retrieved
  - Replay::Message::Reducable - when its possible a reduction can occur
  - Replay::Message::Reducing - when a reduction lock has been supplied
  - Replay::Message::NewCanonical - when we've updated our canonical state

 events consumed:
  - None


#sub revert_all_expired_locks { # maintenance utility
#sub fetch_transitional_state { # external
#sub fetch_canonical_state { # external
#sub store_new_canonical_state { # external
#
#sub state_signature { # signature for state
#
#sub rule { # rule accessor
#sub merge { # Create the desktop by adding canonical
#sub revert { # used by main logic
#sub checkout { #  used by fetch_transitional
#sub emit_lock_error { # utility
#sub expired_lock_recover { # logic to recover from an expired lock
#sub emit_reducable_if_needed { utility
#
#sub new_document { # called by engine implimentations

=head1 STORAGE ENGINE IMPLEMENTATION METHODS 

These methods must be overridden by the specific implementation

They should call super() to cause the emit of control messages when they succeed

=head2 (state) = retrieve ( idkey )

Unconditionally return the entire state document 

This includes all the components of the document model and is usually used internally

This is expected to be something like:

{ Timeblocks => [ ... ]
, Ruleversions => [ { ...  }, { ... }, ... ]
, Windows => [ ... ]
, inbox => [ <unprocessed atoms> ]
, desktop => [ <atoms in processing ]
, canonical => [ a
, locked => signature of a secret uuid with the idkey required to unlock.  presence indicates record is locked.
, lockExpireEpoch => epoch time after which the lock has expired.  not present when not locked
} 

=head2 (success) = absorb ( idkey, message, meta )

Insert a new atom into the indicated state, with metadata

append the new atom atomically to the 'inbox' in the state document referenced
ensure the meta->{Windows} member are in the 'Windows' set in the state document referenced
ensure the meta->{Ruleversions} members are in the 'Ruleversions' set in the state document referenced
ensure the meta->{Timeblocks} members are in the 'Timeblocks' set in the state document referenced


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
      return success
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


=head2 hash = window_all(idkey)

select and return all of the documents representing states within the
specified window, in a hash keyed by the key within the window

=head2 objectlist = find_keys_need_reduce()

returns a list of idkey objects which represent all of the keys in the replay
system that appear to have outstanding absorptions that need reduced.

=head2 objectlist = find_keys_active_checkout()

returns a list of idkey objects which represent all of the keys in the replay
system that appear to be in progress.

=head1 INTERNAL METHODS

=head2 merge($idkey, $alpha, $beta)

Takes two lists and merges them together using the compare ordering from the rule

=head2 new_document

The default new document template filled in

=head2 rule(idkey)

accessor to grab the rule object for a particular idkey

=head2 state_signature

logic that creates a signature from a state - probably used for canonicalSignature field

=head1 AUTHOR

David Ihnen, C<< <davidihnen at gmail.com> >>

=head1 CONFIGURATION AND ENVIRONMENT

Implied by context

=head1 DIAGNOSTICS

nothing to say here

=head1 DEPENDENCIES

Nothing outside the normal Replay world

=head1 INCOMPATIBILITIES

Nothing to report

=head1 BUGS AND LIMITATIONS

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


=head1 ACKNOWLEDGMENTS


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
AND CONTRIBUTORS 'AS IS' AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES.
THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE, OR NON-INFRINGEMENT ARE DISCLAIMED TO THE EXTENT PERMITTED BY
YOUR LOCAL LAW. UNLESS REQUIRED BY LAW, NO COPYRIGHT HOLDER OR
CONTRIBUTOR WILL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, OR
CONSEQUENTIAL DAMAGES ARISING IN ANY WAY OUT OF THE USE OF THE PACKAGE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


=cut

1;    # End of Replay
