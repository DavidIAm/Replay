package Replay::BaseStorageEngine;

use Moose;
use Digest::MD5 qw/md5_hex/;
use Replay::Message::Reducable;
use Replay::Message::Reducing;
use Replay::Message::Reverted;
use Replay::Message::NewCanonical;
use Replay::Message::Fetched;
use Replay::Message::Locked;
use Replay::Message::Unlocked;
use Replay::Message::WindowAll;
use Storable qw/freeze/;
use Try::Tiny;
use Readonly;
use Replay::IdKey;
use Carp qw/croak carp/;

our $VERSION = '0.01';

Readonly my $REDUCE_TIMEOUT => 60;

$Storable::canonical = 1;    ## no critic (ProhibitPackageVars)

Readonly my $READONLY => 1;

has config => (is => 'ro', isa => 'HashRef[Item]', required => 1,);

has ruleSource => (is => 'ro', isa => 'Replay::RuleSource', required => 1);

has eventSystem => (is => 'ro', isa => 'Replay::EventSystem', required => 1);

# accessor - how to get the rule for an idkey
sub rule {
    my ($self, $idkey) = @_;
    my $rule = $self->ruleSource->byIdKey($idkey);
    croak "No such rule $idkey->ruleSpec" unless $rule;
    return $rule;
}

# merge a list of atoms with the existing list in that slot
sub merge {
    my ($self, $idkey, $alpha, $beta) = @_;
    my @sorted = sort { $self->rule($idkey)->compare($a, $b) } @{$alpha},
        @{$beta};
    return [@sorted];
}

sub checkout {
    my ($self, $idkey) = @_;
    return $self->eventSystem->control->emit(
        Replay::Message::Locked->new(Message => { $idkey->hashList }));
}

sub checkin {
    my ($self, $idkey) = @_;
    return $self->eventSystem->control->emit(
        Replay::Message::Unlocked->new(Message => { $idkey->hashList }));
}

sub revert {
    my ($self, $idkey) = @_;
    return $self->eventSystem->control->emit(
        Replay::Message::Reverted->new(Message => { $idkey->hashList }));
}

sub retrieve {
    my ($self, $idkey) = @_;
    return $self->eventSystem->control->emit(
        Replay::Message::Fetched->new(Message => { $idkey->hashList }));
}

sub absorb {
    my ($self, $idkey) = @_;
    return $self->eventSystem->control->emit(
        Replay::Message::Reducable->new(Message => { $idkey->hashList }));
}

sub delayToDoOnce {
    my ($self, $name, $code) = @_;
    use AnyEvent;
    return $self->{timers}{$name} = AnyEvent->timer(
        after => 1,
        cb    => sub {
            delete $self->{timers}{$name};
            $code->();
        }
    );
}

# accessor - given a state, generate a signature
sub stateSignature {
    my ($self, $idkey, $list) = @_;
    return undef unless defined $list;  ## no critic (ProhibitExplicitReturnUndef)
    $self->stringtouch($list);
    return md5_hex($idkey->hash . freeze($list));
}

sub stringtouch {
    my ($self, $struct) = @_;
    $struct .= '' unless ref $struct;
    if ('ARRAY' eq ref $struct) {
        foreach (0 .. $#{$struct}) {
            stringtouch($struct->[$_]) if ref $struct->[$_];
            $struct->[$_] .= '' unless ref $struct->[$_];
        }
    }
    if ('HASH' eq ref $struct) {
        foreach (keys %{$struct}) {
            stringtouch($struct->{$_}) if ref $struct->{$_};
            $struct->{$_} .= '' unless ref $struct->{$_};
        }
    }
    return;
}

sub fetchTransitionalState {
    my ($self, $idkey) = @_;

    my ($uuid, $cubby) = $self->checkout($idkey, $REDUCE_TIMEOUT);

    return unless defined $cubby;

    # drop the checkout if we don't have any items to reduce
    unless (scalar @{ $cubby->{desktop} || [] }) {
        carp "Reverting because we didn't check out any work to do?\n";
        $self->revert($idkey, $uuid);
        return;
    }

    # merge in canonical, moving atoms from desktop
    my $reducing;
    try {
        $reducing
            = $self->merge($idkey, $cubby->{desktop}, $cubby->{canonical} || []);
    }
    catch {
        carp "Reverting because doing the merge caused an exception $_\n";
        $self->revert($idkey, $uuid);
        return;
    };

    # notify interested parties
    $self->eventSystem->control->emit(
        Replay::Message::Reducing->new(Message => { $idkey->hashList }));

    # return uuid and list
    return $uuid => {
        Windows      => $idkey->window,
        Timeblocks   => $cubby->{Timeblocks} || [],
        Ruleversions => $cubby->{Ruleversions} || [],
    } => @{$reducing};

}

sub storeNewCanonicalState {
    my ($self, $idkey, $uuid, $emitter, @atoms) = @_;
    my $cubby = $self->retrieve($idkey);
    $cubby->{canonVersion}++;
    $cubby->{canonical} = [@atoms];
    $cubby->{canonSignature} = $self->stateSignature($idkey, $cubby->{canonical});
    delete $cubby->{desktop};
    my $newstate = $self->checkin($idkey, $uuid, $cubby);
    $emitter->release;

    foreach my $atom (@{ $emitter->atomsToDefer }) {
        $self->absorb($idkey, $atom, {});
    }
    $self->eventSystem->control->emit(
        Replay::Message::NewCanonical->new(Message => { $idkey->hashList }));
    $self->eventSystem->control->emit(
        Replay::Message::Reducable->new(Message => { $idkey->hashList }))
        if scalar @{ $newstate->{inbox} || [] }
        ;                # renotify reducable if inbox has entries now
    return $newstate;    # release pending messages
}

sub fetchCanonicalState {
    my ($self, $idkey) = @_;
    my $cubby = $self->retrieve($idkey);
    my $e = $self->stateSignature($idkey, $cubby->{canonical}) || '';
    if (($cubby->{canonSignature} || '') ne ($e || '')) {
        carp "canonical corruption $cubby->{canonSignature} vs. " . $e;
    }
    $self->eventSystem->control->emit(
        Replay::Message::Fetched->new(Message => { $idkey->hashList }));
    return @{ $cubby->{canonical} || [] };
}

sub windowAll {
    my ($self, $idkey) = @_;
    return $self->eventSystem->control->emit(
        Replay::Message::WindowAll->new(Message => { $idkey->hashList }));
}

sub findKeysNeedReduce {
    my ($self, $idkey) = @_;
    return $self->eventSystem->control->emit(
        Replay::Message->new(MessageType => "FoundKeysForReduce", Message => {}));
}

sub enumerateWindows {
    my ($self, $idkey) = @_;
    croak "unimplemented";
}

sub enumerateKeys {
    my ($self, $idkey) = @_;
    croak "unimplemented";
}

sub new_document {
    my ($self, $idkey) = @_;
    return {
        idkey        => { $idkey->hashList },
        Windows      => [],
        Timeblocks   => [],
        Ruleversions => [],
    };
}

=head1 NAME

Replay::BaseStorageEngine - wrappers for the storage engine implimentation

=head1 VERSION

Version 0.01

=head1 SYNOPSIS

This is the base class for the implimentation specific parts of the Replay system.

    IMPLIMENTATIONCLASS->new(
        config      => $self->config,
        ruleSource  => $self->ruleSource,
        eventSystem => $self->eventSystem,
    );

=head1 SUBROUTINES/METHODS

These methods are used by consumers of the storage class

=head2 success = absorb(idkey, atom, meta)

accept a new atom at a location idkey with metadata attached.  no locking

=head2 statelist = fetchCanonicalState(idkey)

get the canonical state.  no locking

=head2 uuid, statelist = fetchTransitionalState(idkey)

check out a state for transition.  locks record

automatically reverts previous checkout if lock is expired

=head2 success = storeNewCanonicalState(idkey, uuid, emitter, @atoms)

check in a state for transition if uuid matches.  unlocks record if success.

=head1 DATA TYPES

 types:
 - idkey:
  { name: string
  , version: string
  , window: string
  , key: string
  }
 - atom
  { a hashref which is an atom of the state for this compartment }
 - state:
  idkey: the particular state compartment
  list: the list of atoms within that compartment
 - signature: md5 sum 

 interface:
  - boolean absorb(idkey, atom): accept a new atom into a state
  - state fetchTransitionalState(idkey): returns a new key-state for reduce processing
  - boolean storeNewCanonicalState(idkey, uuid, emitter, atoms): accept a new canonical state
  - state fetchCanonicalState(idkey): returns the current collective state

 events emitted:
  - Replay::Message::Fetched - when a canonical state is retrieved
  - Replay::Message::Reducable - when its possible a reduction can occur
  - Replay::Message::Reducing - when a reduction lock has been supplied
  - Replay::Message::NewCanonical - when we've updated our canonical state

 events consumed:
  - None


=head1 STORAGE ENGINE IMPLIMENTATION METHODS 

These methods must be overridden by the specific implimentation

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
, lockExpireEpoch => epoch time after which the lock has expired.  not presnet when not locked
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


=head2 hash = windowAll(idkey)

select and return all of the documents representing states within the
specified window, in a hash keyed by the key within the window

=head2 objectlist = findKeysNeedReduce(idkey)

returns a list of idkey objects which represent all of the keys in the replay
system that appear to be locked, in progress, or have outstanding absorbtions
that need reduced.

=head1 INTERNAL METHODS

=head2 enumerateKeys

not yet implimented

A possible interface that lets a consumer get a list of keys within a window

=head2 enumerateWindows

not yet implimented

A possible interface that lets a consumer get a list of Windows within a domain rule version

=head2 merge($idkey, $alpha, $beta)

Takes two lists and merges them together using the compare ordering from the rule

=head2 new_document

The default new document template filled in

=head2 rule(idkey)

accessor to grab the rule object for a particular idkey

=head2 stateSignature

logic that creates a signature from a state - probably used for canonicalSignature field

=head2 stringtouch(structure)

Attempts to concatenate '' with any non-references to make them strings so that
the signature will be more canonical.

=head2 delayToDoOnce(name, code)

sometimes redundant events are fired in rapid sequence.  This ensures that 
within a short period of time, only one piece of code (distinguished by name)
is executed.  It just uses the AnyEvent timer delaying for a second at this 
point

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

1;    # End of Replay

