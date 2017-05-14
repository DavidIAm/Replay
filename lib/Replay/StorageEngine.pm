package Replay::StorageEngine;

use Moose;
use Try::Tiny;
use English '-no_match_vars';
use Carp qw/croak/;

our $VERSION = '0.03';

has config => ( is => 'ro', isa => 'HashRef[Item]', required => 1, );
has engine =>
    ( is => 'ro', isa => 'Object', builder => '_build_engine', lazy => 1, );
has mode => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
    builder  => '_build_mode',
    lazy     => 1,
);
has ruleSource => ( is => 'ro', isa => 'Replay::RuleSource', required => 1, );
has eventSystem =>
    ( is => 'ro', isa => 'Replay::EventSystem', required => 1, );

# Delegate the api points
sub retrieve {
    my ( $self, @args ) = @_;
    return $self->engine->retrieve(@args);
}

sub absorb {
    my ( $self, @args ) = @_;
    return $self->engine->absorb(@args);
}

sub checkout {
    my ( $self, @args ) = @_;
    return $self->engine->inbox_to_desktop(@args)
}

sub desktop_cursor {
    my ( $self, @args ) = @_;
    return $self->engine->desktop_cursor(@args)
}

sub fetch_canonical_state {
    my ( $self, @args ) = @_;
    return $self->engine->fetch_canonical_state(@args);
}

sub fetch_transitional_state {
    my ( $self, @args ) = @_;
    return $self->engine->fetch_transitional_state(@args);
}

sub revert {
    my ( $self, @args ) = @_;
    return $self->engine->revert(@args);
}

sub store_new_canonical_state {
    my ( $self, @args ) = @_;
    return $self->engine->store_new_canonical_state(@args);
}

sub window_all {
    my ( $self, @args ) = @_;
    return $self->engine->window_all(@args);
}

sub find_keys_need_reduce {
    my ( $self, @args ) = @_;
    return $self->engine->find_keys_need_reduce(@args);
}

sub _build_engine {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my ( $self, @args ) = @_;
    my $classname = $self->mode;

    if ( !$classname->does('Replay::Role::StorageEngine') ) {
        croak $classname
            . q( -->Must use the Replay::Role::StorageEngin 'Role' );

    }

    my $new = $classname->new(
        config      => $self->config,
        ruleSource  => $self->ruleSource,
        eventSystem => $self->eventSystem,
    );
    return $new;
}

sub _build_mode {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my ( $self, @args ) = @_;
    if ( not $self->config->{StorageEngine}{Mode} ) {
        croak q(No StorageMode?);
    }
    my $class
        = 'Replay::StorageEngine::' . $self->config->{StorageEngine}{Mode};
    try {
        my $path = $class . '.pm';
        $path =~ s{::}{/}gxsm;
        if ( eval { require $path } ) {
        }
        else {
            croak $EVAL_ERROR;
        }
    }
    catch {
        confess q(No such storage mode available )
            . $self->config->{StorageEngine}{Mode}
            . " --> $_";
    };
    return $class;
}

1;

__END__

=pod

=head1 NAME

Replay::StorageEngine - abstracted interface to the storage portion of the Replay system

=head1 VERSION

Version 0.01

=head1 SYNOPSIS

This is the implementation agnostic interface for the storage portion of the Replay system.

You can instantiate a StorageEngine object with a list of rules and config

use Replay::StorageEngine;

my $storage = Replay::StorageEngine->new( ruleSource => $ruleSource, config => { StorageMode => 'Memory', engine_specific_config => 'as_relevant' } );

=head1 CONFIGURATION AND ENVIRONMENT

Implied by context

=head1 DESCRIPTION

The data model consists of a series of locations represented by 'idkey' type.

The ID type has a NAMESPACE series of axis such as 'name', and 'version', but 
could also contain 'domain', 'system', 'worker', 'client', or any other set 
of divisions as suits the application

All id types contain 'window' (the bitemporality axis)

All id types contain 'key' (the reduction grouping axis)

Each state of the application is formed of a series of identically typed objects.

When a rule decides that information may be interesting and may affect the
state, it sends the object with the idkey that it has been mapped to to the
absorb function

The absorb function adds the object to its inbox list, and an event is emitted
on the control channel 'Replay::Message::Reducable' indicating that a state 
transition is possible within this idkey slot.

When a worker hears the Reducable message, it may call the storage engine with the
fetch_transitional_state method.  This may be called by all workers almost 
simultaneously as all workers are available.  If there is no inbox available 
due to being gotten by a previous caller, nothing will be returned.  This lock
transitions the idkey slot to reducing state.  The merge of the inbox and the
canonical state is returned to the caller with a signature.  The signature and 
reduction state is persisted.  A 'Replay::Message::Reducing' message will be 
emitted on the control channel.

When a worker has completed its reduction process, it calls the storage engine
with the store_new_canonical_state method.  The previously supplied signature
will be used to validate that it is operating on the latest delivered state.  
(it is possible that the reduce timed out, and more entries were added to the
inbox and merged in!)  If the signature does not match, the data is dropped,
the worker should not emit any derived events in relation to the data reduced.
If the signature matches, the canonical state is replaced, the version number
for the canonical state is incremented, a signature for the canonical state 
is stored and success is returned.  Upon successful commit, a 
'Replay::Message::NewCanonical' message will be emitted on the control channel

When any system wishes to get the current canonical state it may call the 
fetch_canonical_state method.  The current canonical state and signature is 
returned to the client. Upon successful commit, a 'Replay::Message::Fetched'
message is emitted on the control channel

=head1 SUBROUTINES/METHODS

=head2 retrieve(idkey)

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


=head2 absorb(idkey, atom, meta)

absorb a new atom into the storage system.

call engine absorb

append the new atom atomically to the 'inbox' in the state document referenced
ensure the meta->{Windows} member are in the 'Windows' set in the state document referenced
ensure the meta->{Ruleversions} members are in the 'Ruleversions' set in the state document referenced
ensure the meta->{Timeblocks} members are in the 'Timeblocks' set in the state document referenced

=head2 (@state) = fetch_canonical_state(idkey)

call engine retrieve an return the canonical list

retrieve the list of atoms defining the canonical state for this idkey
no locking is performed

=head2 (uuid, @state) = fetch_transitional_state(idkey)

call engine checkout

merge canonical and desktop with the compare rule for ordering



triggers a checkout of the state which consists of:

uuid - generated
lock - the document is atomically locked with idkey+uuid hash
lockExpireEpoch - set to the current epoch plus timeout seconds
inbox - renamed/moved to desktop
canonical list - merged with desktop list, sorted per rule bit 'compare'
uuid and merged list returned

=head2 revert(idkey, uuid) 

call engine revert

causes a revert of the checkout. - only works if the signature with the uuid supplied matches the lock or the lock is expired

lock - reset with a new hash (append UNLOCKING to the hashed idkey/uuid string) 
lockExpireEpoch - reset with a new time
desktop - each atom is re-absorbed into the record
once that all is accomplished:
desktop - deleted
lock - deleted
lockExpireEpoch - deleted

=head2 store_new_canonical_state(idkey, uuid, emitter, @state)

see BaseStorageEngine store_new_canonical_state



=head2 window_all(idkey)

see BaseStorageEngine window_all

=head2 find_keys_need_reduce(idkey)

see BaseStorageEngine find_keys_need_reduce

=head1 AUTHOR

David Ihnen, C<< <davidihnen at gmail.com> >>

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


=head1 STORAGE ENGINE MODEL ASSUMPTIONS

IdKey: object that indicates all the axis of selection for the data requested
Atom: defined by the rule being processed; storage engine shouldn't care about it.

STATE DOCUMENT GENERAL TO STORAGE ENGINE

inbox: [ Array of Atoms ] - freshly arrived atoms are stored here.
canonical: [ Array of Atoms ] - the current reduced 
canonSignature: q(SIGNATURE) - a sanity check to see if this canonical has been mucked with
Timeblocks: [ Array of input timeblock names ]
Ruleversions: [ Array of objects like { name: <rulename>, version: <ruleversion> } ]

STATE DOCUMENT SPECIFIC TO THIS IMPLEMENTATION

db is determined by idkey->ruleversion
collection is determined by idkey->collection
idkey is determined by idkey->cubby

desktop: [ Array of Atoms ] - the previously arrived atoms that are currently being processed
locked: q(SIGNATURE) - if this is set, only a worker who knows the signature may update this
lockExpireEpoch: TIMEINT - used in case of processing timeout to unlock the record

STATE TRANSITIONS IN THIS IMPLEMENTATION 

checkout

rename inbox to desktop so that any new absorbs don't get confused with what is being processed

=head1 STORAGE ENGINE IMPLEMENTATION METHODS 

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

