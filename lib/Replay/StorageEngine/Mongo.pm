package Replay::StorageEngine::Mongo;

use Moose;
with qw (Replay::Role::MongoDB Replay::Role::StorageEngine );
use Replay::IdKey;
use Readonly;
use JSON;
use Carp qw/confess croak carp/;
use Replay::Message::Reducable;
use Replay::Message::Cleared::State;
use Replay::Message;
use Data::Dumper;
our $VERSION = 0.02;

sub retrieve {
    my ( $self, $idkey ) = @_;
    my $doc = $self->document($idkey);
    return $doc;
}

sub has_inbox_outstanding {
    my ( $self, $idkey ) = @_;
    return $self->count_inbox_outstanding($idkey);
}

sub cursor_each {
    my ( $self, $cursor, $callback ) = @_;
    my $break = 1;
    while ($break) {
        my @list = $cursor->batch;
        $break = 0 if 0 == scalar @list;
        foreach (@list) { $callback->($_); }
    }
    return ();
}

sub expire_all_locks {
    my ($self) = @_;
    my %locks =
        map { ( $_->{idkey}, $_ ) }
            $self->BOXES->find( { locked => { q^$^ . 'exists' => 1 } },
            { idkey => 1, locked => 1 } )->all;
    foreach ( values %locks ) {
        my $key = Replay::IdKey->from_full_spec( $_->{idkey} );
        my ($lock) = $self->expired_lock_recover($key);
        if ( $lock->is_locked ) {
            $self->revert($lock);
        }
    }
}

sub ensure_locked {
    my ( $self, $lock ) = @_;

    my ( $package, $filename, $line ) = caller;
    my $curlock = $self->lockreport( $lock->idkey );
    warn " $$ "
        . $curlock->matches($lock)
        . 'This document '
        . $lock->idkey->cubby
        . ' isn\'t locked with this signature ('
        . ( $lock->locked    || q^^ ) . q/!=/
        . ( $curlock->locked || q^^ ) . ")\n"
        if !$curlock->matches($lock);
    return $curlock->matches($lock);
}

# TODO: call this or something like it!
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

sub checkin {
    my ( $self, $lock, $state ) = @_;

    # warn('Replay::StorageEngine::Mongo checkin' );
    my $result = $self->update_and_unlock( $lock, $state );
    $self->purge($lock);

    return if not defined $result;
    return $result;
}

sub revert_this_record {
    my ( $self, $lock ) = @_;

    my $current = $self->lockreport( $lock->idkey );
    croak " $$ cannot revert record is not locked" if !$lock->locked;
    croak " $$  cannot revert because this is not my lock - sig "
        . $current->locked
        . ' lock '
        . $lock->locked . ' or '
        if !$lock->matches($current);
    croak " $$ cannot revert because this lock is expired "
        . ( $lock->{lockExpireEpoch} - time )
        . ' seconds overdue.'
        if $lock->is_expired;

    # reabsorb all of the desktop atoms into the document
    my $r = $self->reabsorb($lock);

    my $unlock = $self->just_unlock($lock);
    return $lock;
}

sub _build_dbpass {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my $self   = shift;
    my $dbpass = $self->config->{StorageEngine}{Pass};
    return $dbpass;
}

sub _build_dbuser {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my $self   = shift;
    my $dbuser = $self->config->{StorageEngine}{User};
    return $dbuser;
}

sub _build_dbauthdb {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my $self = shift;
    my $auth = $self->config->{StorageEngine}{AuthDB} || 'admin';
    return $auth;
}

sub _build_dbname {      ## no critic (ProhibitUnusedPrivateSubroutines)
    my $self   = shift;
    my $dbname = $self->config->{stage} . '-replay';
    return $dbname;
}

sub _build_db {          ## no critic (ProhibitUnusedPrivateSubroutines)
    my ($self) = @_;
    my $config = $self->config;
    my $db     = $self->mongo->get_database( $self->dbname );
    return $db;
}

1;

__END__

=pod

=head1 NAME

Replay::StorageEngine::Mongo - storage implementation for mongodb

=head1 VERSION

Version 0.04

=head1 DESCRIPTION

This is the Storage engine implementation for mongodb

=head1 SYNOPSIS


Replay::StorageEngine::Mongo->new( ruleSource => $rs, eventSystem => $es, config => { Mongo => { host: ..., port: ... } } );

=head1 OVERRIDES

=head2 retrieve - get document

=head2 absorb - add atom

=head2 checkout - lock and return document

=head2 revert - revert and unlock document

=head2 checkin - update and unlock document

=head2 window_all - get documents for a particular window

=head2 find_keys_need_reduce - find all the keys that look like they might need reduction

=head1 SUBROUTINES/METHODS

=head2 _build_mongo

mongo builder/connector

=head2 _build_db

get the object for the db client that indicates the db the document is in

=head2 _build_uuid

make an object with which to generate uuids

=head2 collection

get the object for the db client that indicates the collection this document is in

=head2 document

return the document indicated by the idkey

=head2 generate_uuid

create and return a new uuid

=head2 checkout_record(idkey, signature)

This will return the uuid and document, when the state it is trying to open is unlocked and unexpired

otherwise, it returns undef.

=head2 relock(idkey, oldsignature, newsignature)

Given a valid oldsignature, updates the lock time and installs the new signature

returns the state document, or undef if signature doesn't match or it is not locked

=head2 update_and_unlock(idkey, signature)

updates the state document, and unlocks the record.

returns the state document, or undef if the state is not locked with that signature

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
