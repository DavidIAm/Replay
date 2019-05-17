package Replay::StorageEngine::Memory;

use Moose;
with 'Replay::Role::StorageEngine';
use Scalar::Util qw/blessed/;
use Replay::StorageEngine::Memory::Cursor;
use Replay::Message::NoLock::DuringRevert;
use Replay::Message::Cleared::State;
use Replay::IdKey;
use Set::Scalar;
use Set::Object;
use Data::Dumper;
   
use Carp qw/croak carp cluck/;

has 'debug' => ( is => 'rw' );
our $VERSION = q(0.02);

my $store = {};

sub retrieve {
    my ( $self, $idkey ) = @_;
    return $self->collection($idkey)->{ $idkey->cubby }
        ||= $self->new_document($idkey);
}

# find_keys_need_reduce is tighly coupled to this logic!
sub BOXES {
    my ( $self, $idkey ) = @_;
    return $self->{BOXES}{ $idkey->full_spec } ||= [];
}

sub desktop_cursor {
    my ( $self, $lock ) = @_;
    $self->ensure_locked($lock);
    return Replay::StorageEngine::Memory::Cursor->new(
        grep { $_->{state} eq 'desktop' } @{ $self->BOXES( $lock->idkey ) } );
}

sub inbox_to_desktop {
    my ( $self, $lock ) = @_;
    return
        scalar map { $_->{state} = 'desktop' }
        @{ $self->BOXES( $lock->idkey ) };
}

# State transition = add new atom to inbox
sub absorb {
    my ( $self, $idkey, $atom, $meta ) = @_;

    return push @{ $self->BOXES($idkey) },
        {
        idkey => $idkey->full_spec,
        meta  => $meta,
        atom  => $atom,
        state => 'inbox',
        };
}

sub checkout_record {
    my ( $self, $lock ) = @_;

    my $state = $self->retrieve( $lock->idkey );
    carp 'PRECHECKOUT STATE' . $state if $self->{debug};
    return Replay::StorageEngine::Lock->empty( $lock->idkey )
        if $state->{locked};
    $state->{locked}            = $lock->locked;
    $state->{lockExpireEpoch}   = $lock->lockExpireEpoch;
    $state->{reducable_emitted} = 0;
    carp 'POSTCHECKOUT STATE' . $state if $self->{debug};

    return $lock;
}

sub purge {
    my ( $self, $idkey ) = @_;
    my $document = delete $self->collection($idkey)->{ $idkey->cubby };
    if ( exists $document->{canonical} ) {
        $self->collection($idkey) = $document;
        confess "Tried to clear a non-empty canonical. Sorry.\n";
    }
    return $document;
}


sub has_inbox_outstanding {
    my ( $self, $idkey ) = @_;
    return 0; #stub in for now
}

sub document_exists {
    my ( $self, $idkey ) = @_;
    return exists $self->collection($idkey)->{ $idkey->cubby };
}

sub relock_expired {
    my ( $self, $lock ) = @_;

    # Lets try to get an expire lock, if it has timed out
    return if !$self->document_exists( $lock->idkey );
    my $state = $self->retrieve( $lock->idkey );
    return $state     if $state->{locked} eq $lock->locked;
    carp 'NOT LOCKED' if !exists $state->{locked};
    carp 'NO EPOCH'   if !exists $state->{lockExpireEpoch};
    carp 'UNEXPIRED ( ' . $state->{lockExpireEpoch} . ')'
        if $state->{lockExpireEpoch} > time;
    return if !exists $state->{locked};
    return
        if exists $state->{lockExpireEpoch}
        && $state->{lockExpireEpoch} >= time;
    $state->{locked}          = $lock->locked;
    $state->{lockExpireEpoch} = $lock->lockExpireEpoch;

    return $state;
}

sub checkin {
    my ( $self, $lock, $state ) = @_;

    my $result = $self->update_and_unlock( $lock, $state );

    # if any of these three exist, we maintain state
    return $result
        if scalar grep { $_->{state} eq 'inbox' }
        @{ $self->BOXES( $lock->idkey ) };
    return $result if exists $result->{canonical};

    # otherwise we clear it entirely
    $self->purge( $lock->idkey );

    $self->eventSystem->control->emit(
        Replay::Message::Cleared::State->new( $lock->idkey->hash_list ),
    );

    return;
}

sub window_all {
    my ( $self, $idkey ) = @_;
    my $collection = $self->collection($idkey);
    return {
        map { $collection->{$_}{idkey}{key} => $collection->{$_}{canonical} }
            grep { 0 == index $_, $idkey->window_prefix }
            keys %{$collection} };
}

sub ensure_locked {
    my ( $self, $lock ) = @_;
    my $document = $self->retrieve( $lock->idkey );
    croak 'This document isn\'t locked with this signature ('
        . ( $document->{locked} || q^^ ) . q/,/
        . ( $lock->locked || q^^ ) . ')'
        if !$lock->is_mine( $document->{locked} );
    return 1;
}

sub revert_this_record {
    my ( $self, $lock ) = @_;

    $self->ensure_locked($lock);

    # reabsorb all of the desktop atoms into the document
    foreach ( @{ $self->BOXES( $lock->idkey ) } ) { $_->{state} = 'inbox'; }

    $self->just_unlock($lock);
    return;
}

sub just_unlock {
    my ( $self, $lock ) = @_;

    $self->ensure_locked($lock);
    my $state = $self->retrieve( $lock->idkey );
    delete $state->{locked};
    delete $state->{lockExpireEpoch};
    return;
}

sub update_and_unlock {
    my ( $self, $lock, $state ) = @_;
    return                           if !exists $state->{locked};
    carp 'LOCKED' . $state->{locked} if $self->debug;
    return                           if !$lock->is_proper( $state->{locked} );
    @{ $self->BOXES( $lock->idkey ) }
        = grep { $_->{state} ne 'desktop' } @{ $self->BOXES( $lock->idkey ) };

    if ( @{ $state->{canonical} || [] } == 0 ) {
        delete $state->{canonical};
    }
    $self->just_unlock($lock);
    return $state;
}

sub collections {
    my ($self) = @_;
    return keys %{$store};
}

sub collection {
    my ( $self, $idkey ) = @_;
    my $name = $idkey->collection();
     carp 'POSTIION NAME' . $name . ' - ' . $idkey->cubby if $self->{debug};
    return $store->{$name} ||= {};
}

sub find_keys_need_reduce {

    my ($self) = @_;

    #    carp('Replay::StorageEngine::Memory  find_keys_need_reduce'. $self );
    my @idkeys = ();
    my $rule;
    while ( $rule
        = $rule ? $self->ruleSource->next : $self->ruleSource->first )
    {
        my $idkey = Replay::IdKey->new(
            name    => $rule->name,
            version => $rule->version,
            window  => q^-^,
            key     => q^-^
        );
        push @idkeys, map {
            Replay::IdKey->new(
                name    => $rule->name,
                version => $rule->version,
                Replay::IdKey->parse_cubby( $_->{idkey} )
            );
            } grep { exists $_->{locked} || exists $_->{lockExpireEpoch} }
            values %{$store};
    }

    # Tightly coupled to BOXES and how it stores information
    push @idkeys,
        map { Replay::IdKey->new( Replay::IdKey->parse_spec( $_->spec ) ) }
        grep { 0 < scalar @{ $self->{BOXES}{$_} || [] } }
        keys %{ $self->{BOXES} };
    return @idkeys;
}

1;

__END__

=pod

=head1 NAME

Replay::StorageEngine::Memory - storage implementation for in-process memory - testing only

=head1 VERSION

Version 0.01

=head1 SYNOPSIS

Replay::StorageEngine::Memory->new( ruleSource => $rs, eventSystem => $es, config => {...} );

=head1 DESCRIPTION

Stores the entire storage partition in package memory space.  Anybody in
this process can access it as if it is a remote storage solution... only
faster.

=head1 SUBROUTINES/METHODS

=head2 retrieve - get document

=head2 absorb - add atom

=head2 checkout - lock and return document

=head2 revert - revert and unlock document

=head2 checkin - update and unlock document

=head2 window_all - get documents for a particular window

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

1;

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

1;
