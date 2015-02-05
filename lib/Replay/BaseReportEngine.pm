package Replay::BaseReportEngine;

use Moose;
use Digest::MD5 qw/md5_hex/;

use Replay::Message::Report::NewDelivery;
use Replay::Message::Report::NewSummary;
use Replay::Message::Report::NewGlobSummary;
use Replay::Message::Report::Freeze;
use Replay::Message::Report::CopyDomain;
use Replay::Message::Report::Checkpoint;
use Replay::Message::Report::PurgedDelivery;
use Replay::Message::Report::PurgedSummary;
use Replay::Message::Report::PurgedGlobSummary;
use Replay::Message::Locked;
use Replay::Message::Unlocked;
use Replay::Message::WindowAll;
use Storable qw//;
use Try::Tiny;
use Readonly;
use Replay::IdKey;
use Carp qw/croak carp/;

our $VERSION = '0.03';

$Storable::canonical = 1;    ## no critic (ProhibitPackageVars)

Readonly my $REPORT_TIMEOUT => 60;
Readonly my $READONLY       => 1;

has config => (is => 'ro', isa => 'HashRef[Item]', required => 1,);

has ruleSource => (is => 'ro', isa => 'Replay::RuleSource', required => 1);

has eventSystem => (is => 'ro', isa => 'Replay::EventSystem', required => 1);

# accessor - how to get the rule for an idkey
sub rule {
    my ($self, $idkey) = @_;
    my $rule = $self->ruleSource->by_idkey($idkey);
    croak "No such rule $idkey->rule_spec" if not defined $rule;
    return $rule;
}

sub delete_latest_delivery {
    my ($self, $idkey) = @_;
    $self->delete_latest_revision($idkey->delivery);
    $self->eventSystem->control->emit(
        Replay::Message::Report::PurgedDelivery->new($idkey->marshall));
}
sub delete_latest_summary {
    my ($self, $idkey) = @_;
    $self->delete_latest_revision($idkey->summary);
    $self->eventSystem->control->emit(
        Replay::Message::Report::PurgedSummary->new($idkey->marshall));
}
sub delete_latest_globsummary {
    my ($self, $idkey) = @_;
    $self->delete_latest_revision($idkey->globsummary);
    $self->eventSystem->control->emit(
        Replay::Message::Report::PurgedGlobSummary->new($idkey->marshall));
}

# store a new 
sub update_delivery {
    my ($self, $idkey, @state) = @_;
    my $rule = $self->rule($idkey);
    return unless $rule->can('delivery');
    return $self->delete_latest_delivery($idkey) unless scalar @state;
    $self->store_delivery($idkey, $rule->delivery(@state));
    $self->eventSystem->control->emit(
        Replay::Message::Report::NewDelivery->new($idkey->marshall));
}

sub update_summary {
    my ($self, $idkey, @state) = @_;
    my $rule = $self->rule($idkey);
    return unless $rule->can('summary');
    return $self->delete_latest_summary($idkey) unless scalar @state;
    $self->store_summary($idkey, $rule->summary(@state));
    return $self->eventSystem->control->emit(
        Replay::Message::Report::NewSummary->new($idkey->marshall ));
}

sub update_globsummary {
    my ($self, $idkey, @state) = @_;
    my $rule = $self->rule($idkey);
    return unless $rule->can('globsummary');
    return $self->delete_latest_globsummary($idkey) unless scalar @state;
    $self->store_globsummary($idkey, $rule->globsummary(@state));
    return $self->eventSystem->control->emit(
        Replay::Message::Report::NewGlobSummary->new(
            $idkey->marshall
        )
    );
}

#report on a key
sub delivery {    #get the named documet lates version
    my ($self, $idkey) = @_;
    return $self->do_retrieve($idkey->delivery);
}

# reports on a windows and a key
sub summary {    #
    my ($self, $idkey) = @_;
    return $self->do_retrieve($idkey->summary);
}

# reports all windows for a rule version
sub globsummary {
    my ($self, $idkey) = @_;
    return $self->do_retrieve($idkey->globsummary);
}

sub do_retrieve {
  my ($self, $idkey) = @_;
  my $result = $self->retrieve($idkey);
    confess "retrieve in storage engine implimentation must return hash" unless 'HASH' eq ref $result;
    confess "retrieve in storage engine implimentation must have DATA key" unless exists $result->{DATA};
    confess "retrieve in storage engine implimentation must have FORMATTED key" unless exists $result->{FORMATTED};
    return $result;
}

# get the revsion that is returning
sub revision {
    my ($self, $idkey, $directory) = @_;
    if ($idkey->revision_is_default) {
        return $self->latest($idkey);
    }
    else {
        return $idkey->revision;
    }
}

sub fetch_summary_data {
  confess "unimplimented";
}

sub fetch_globsummary_data {
  confess "unimplimented";
}

sub freeze {
    my ($self, $idkey) = @_;
    return $self->eventSystem->control->emit(
        Replay::Message::Report::Freeze->new($idkey->marshall) );
}

sub copydomain {
    my ($self, $idkey) = @_;
    return $self->eventSystem->control->emit(
        Replay::Message::Report::CopyDomain->new($idkey->marshall ));
}

sub checkpoint {
    my ($self, $idkey) = @_;
    return $self->delay_to_do_once(
        $idkey->hash . 'Reducable',
        sub {
            $self->eventSystem->control->emit(
                Replay::Message::Report::Checkpoint->new($idkey->marshall ));
        }
    );
}

sub delay_to_do_once {
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

1;

__END__

=pod

=head1 NAME

Replay::BaseReportEngine - wrappers for the storage engine implimentation

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

=head2 ( uuid, meta, state ) = fetch_transitional_state(idkey)

uuid is a key used for the new lock that will be obtained on this record

meta is a hash with keys, critical to emit new events
    Windows      =>
    Timeblocks   =>
    Ruleversions =>

state is an array of atoms

=head2 store_new_canonical_state ( idkey, uuid, emitter, atoms )

if the lock indicated by uuid is still valid, stores state (a list of atoms) 
into the canonical state of this cubby.  called 'release' on the emitter object,
also issues absorb calls on the storage engine for each atom listed in the array
ref returned by 'atomsToDefer' from the emitter object

=head2 fetch_canonical_state ( idkey )

simply returns the list of atoms that represents the previously stored 
canonical state of this cubby

=head2 delivery ( idkey, state )

return the output of the delivery method of the rule indicated with the given state

=head2 summary ( idkey, deliveries )

return the output of the summary method of the rule indicated with the given delivery reports

=head2 globsummary ( idkey, summaries )

return the output of the globsummary method of the rule indicated with the given summary reports

=head2 freeze ( $idkey )

the base method that emits the freeze report message

=head2 freezeWindow ( idkey window )

return the success of the freeze operation on the window level delivery report

=head2 freezeGlob ( idkey )

return the success of the freeze operation on the rule level delivery report

=head2 checkpoint ( domain )

freeze and tag everything.  return the checkpoint identifier when complete

=head2 copydomain ( newdomain, oldcheckpoint )

create a new domain starting from an existing checkpoint

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


=head1 INTERNAL METHODS

=head2 rule(idkey)

accessor to grab the rule object for a particular idkey

=head2 stringtouch(structure)

Attempts to concatenate q() with any non-references to make them strings so that
the signature will be more canonical.

=head2 delay_to_do_once(name, code)

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

