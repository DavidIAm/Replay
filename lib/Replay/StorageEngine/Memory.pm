package Replay::StorageEngine::Memory;

use Moose;
use Scalar::Util qw/blessed/;
use Replay::Message::NoLockDuringRevert;
use Replay::Message::ClearedState;
use Replay::IdKey;
use Carp qw/croak carp cluck/;

extends 'Replay::BaseStorageEngine';

our $VERSION = q(0.02);

my $store = {};

override retrieve => sub {
    my ($self, $idkey) = @_;
    super();
    return $self->collection($idkey)->{ $idkey->cubby }
        ||= $self->new_document($idkey);
};

# State transition = add new atom to inbox
override absorb => sub {
    my ($self, $idkey, $atom, $meta) = @_;
    $meta ||= {};
    my $state = $self->retrieve($idkey);

    # unique list of Windows
    my %windows = map { $_ => 1 } @{ $state->{Windows} }, $idkey->window;
    $state->{Windows} = [ keys %windows ];

    # unique list of Timeblocks
    my %timeblocks = map { $_ => 1 } grep {$_} @{ $state->{Timeblocks} },
        $meta->{timeblock};
    $state->{Timeblocks} = [ keys %timeblocks ];

    # unique list of Ruleversions
    my %ruleversions = ();
    foreach my $m (@{ $state->{Ruleversions} }, $meta->{ruleversion}) {
        $ruleversions{ join q(+), map { $_ . q(-) . $m->{$_} } sort keys %{$m} } = $m;
    }
    $state->{Ruleversions} = [ values %ruleversions ];
    push @{ $state->{inbox} ||= [] }, $atom;
    super();
    return 1;
};

sub checkout_record {
    my ($self, $idkey, $signature, $timeout) = @_;

    # try to get lock
    my $state = $self->retrieve($idkey);
    use Data::Dumper;
    warn "PRECHECKOUT STATE" . $state if $self->{debug};
    return if exists $state->{desktop};
    return if exists $state->{locked};
    $state->{locked}          = $signature;
    $state->{lockExpireEpoch} = time + $timeout;
    $state->{desktop}           = delete $state->{inbox} || [];
    warn "POSTCHECKOUT STATE" . $state if $self->{debug};
#    warn "POSTCHECKOUT STATE" . Dumper $self->collection($idkey) if $self->{debug};
    return $state;
}

sub relock {
    my ($self, $idkey, $current_signature, $new_signature, $timeout) = @_;

    # Lets try to get an expire lock, if it has timed out
    my $state = $self->retrieve($idkey);
    return unless $state;
    return unless $state->{locked} eq $current_signature;
    $state->{locked} = $new_signature;
    $state->{lockExpireEpoch} = time + $timeout;

    return $state
}

sub purge {
    my ($self, $idkey) = @_;
    return delete $self->collection($idkey)->{$idkey->cubby};
}
sub exists {
    my ($self, $idkey) = @_;
    return exists $self->collection($idkey)->{$idkey->cubby};
}
sub relock_expired {
    my ($self, $idkey, $signature, $timeout) = @_;

    # Lets try to get an expire lock, if it has timed out
    return unless $self->exists($idkey);
    my $state = $self->retrieve($idkey);
    return $state if $state->{locked} eq $signature;
    warn "NOT LOCKED" unless exists $state->{locked};
    warn "NO EPOCH" unless exists $state->{lockExpireEpoch};
    warn "UNEXPIRED ( $state->{lockExpireEpoch})" if $state->{lockExpireEpoch} > time;
    return unless exists $state->{locked};
    return if exists $state->{lockExpireEpoch} && $state->{lockExpireEpoch} >= time;
    $state->{locked} = $signature;
    $state->{lockExpireEpoch} = time + $timeout;

    return $state;
}


override checkin => sub {
    my ($self, $idkey, $uuid, $state) = @_;

    my $result = $self->update_and_unlock($idkey, $uuid, $state);
    # if any of these three exist, we maintain state
    return $result if exists $result->{inbox};
    return $result if exists $result->{desktop};
    return $result if exists $result->{canonical};
    # otherwise we clear it entirely
    $self->purge($idkey);

        $self->eventSystem->emit('control',
                Replay::Message::ClearedState->new( $idkey->hash_list ),
        );

    super();
    return;
};

override window_all => sub {
    my ($self, $idkey) = @_;
    my $collection = $self->collection($idkey);
    return {
        map {
            $collection->{$_}{idkey}{key} =>
                $collection->{$_}{canonical}
            } grep { 0 == index $_, $idkey->window_prefix }
            keys %{ $collection }
    };
};

override revert => sub {
    my ($self, $idkey, $uuid) = @_;
    my $signature    = $self->state_signature($idkey, [$uuid]);
    my $unluuid      = $self->generate_uuid;
    my $unlsignature = $self->state_signature($idkey, [$unluuid]);
    my $state        = $self->retrieve($idkey);
    if (exists $state->{locked} && $state->{locked} ne $signature) {
        carp q(tried to do a revert but didn't have a lock on it);
        $self->eventSystem->emit('control',
            Replay::Message::NoLockDuringRevert->new( $idkey->hash_list),
        );
    }

    $state->{locked}          = $unlsignature;
    $state->{lockExpireEpoch} = time + $self->timeout;

    $self->revert_this_record($idkey, $unlsignature, $state);
    my $result = $self->unlock($idkey, $unluuid, $state);
    return defined $result;
};

sub revert_this_record {
    my ($self, $idkey, $signature, $document) = @_;

    my $state = $self->retrieve($idkey);
    croak
        "This document isn't locked with this signature ($document->{locked},$signature)"
        if $document->{locked} ne $signature;

    # reabsorb all of the desktop atoms into the document
    foreach my $atom (@{ $document->{'desktop'} || [] }) {
        $self->absorb($idkey, $atom);
    }

    # and clear the desktop state
    my $desktop = delete $state->{desktop};
    return $desktop;
};

sub update_and_unlock {
    my ($self, $idkey, $uuid, $state) = @_;
    my $signature = $self->state_signature($idkey, [$uuid]);
    return unless exists $state->{locked};
    warn "LOCKED" .$state->{locked};
    return unless $state->{locked} eq $signature;
    delete $state->{desktop};            # there is no more desktop on checkin
    delete $state->{lockExpireEpoch};    # there is no more expire time on checkin
    delete $state->{locked};    # there is no more locked signature on checkin
    if (@{ $state->{canonical} || [] } == 0) {
        delete $state->{canonical};
    }
    return $state;
}

sub collection {
    my ($self, $idkey) = @_;
    my $name = $idkey->collection();
    use Data::Dumper;
    warn "POSTIION NAME" . $name . " - " . $idkey->cubby if $self->{debug};
    return $store->{ $name } ||= {};
}

1;

__END__

=pod

=head1 NAME

Replay::StorageEngine::Memory - storage implimentation for in-process memory - testing only

=head1 VERSION

Version 0.01

=head1 SYNOPSIS

Replay::StorageEngine::Memory->new( ruleSoruce => $rs, eventSystem => $es, config => {...} );

Stores the entire storage partition in package memory space.  Anybody in
this process can access it as if it is a remote storage solution... only
faster.

=head1 OVERRIDES

=head2 retrieve - get document

=head2 absorb - add atom

=head2 checkout - lock and return document

=head2 revert - revert and unlock document

=head2 checkin - update and unlock document

=head2 window_all - get documents for a particular window

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
canonSignature: q(SIGNATURE) - a sanity check to see if this canonical has been mucked with
Timeblocks: [ Array of input timeblock names ]
Ruleversions: [ Array of objects like { name: <rulename>, version: <ruleversion> } ]

STATE DOCUMENT SPECIFIC TO THIS IMPLIMENTATION

db is determined by idkey->ruleversion
collection is determined by idkey->collection
idkey is determined by idkey->cubby

desktop: [ Array of Atoms ] - the previously arrived atoms that are currently being processed
locked: q(SIGNATURE) - if this is set, only a worker who knows the signature may update this
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
