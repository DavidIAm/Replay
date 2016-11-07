package Replay::Role::ReportEngine;

use Moose::Role;
use Digest::MD5 qw/md5_hex/;

use Replay::Message::Report::New::Delivery;
use Replay::Message::Report::New::Summary;
use Replay::Message::Report::New::GlobSummary;
use Replay::Message::Report::Freeze;
use Replay::Message::Report::Copy::Domain;
use Replay::Message::Report::Checkpoint;
use Replay::Message::Report::Purged::Delivery;
use Replay::Message::Report::Purged::Summary;
use Replay::Message::Report::Purged::GlobSummary;
use Storable qw//;
use Try::Tiny;
use Readonly;
use Replay::IdKey;
use Carp qw/croak carp/;

our $VERSION = '0.03';

requires qw/retrieve store freeze delivery_keys summary_keys Name thisConfig/;

$Storable::canonical = 1;    ## no critic (ProhibitPackageVars)

Readonly my $REPORT_TIMEOUT => 60;
Readonly my $READONLY       => 1;

has config => ( is => 'ro', isa => 'HashRef[Item]', required => 1, );

has ruleSource => ( is => 'ro', isa => 'Replay::RuleSource', required => 1 );

has eventSystem => ( is => 'ro', isa => 'Replay::EventSystem', required => 1 );
has mode => ( is => 'ro', isa => 'Str', required => 1 );

# accessor - how to get the rule for an idkey
sub rule {
    my ( $self, $idkey ) = @_;
    my $rule = $self->ruleSource->by_idkey($idkey);
    croak "No such rule $idkey->rule_spec" if not defined $rule;
    return $rule;
}

sub notify_purge {
    my ( $self, $idkey, $part ) = @_;
    return $self->eventSystem->control->emit(
        Replay::Message::Report::PurgedDelivery->new( $idkey->marshall ) )
      if ( $part eq 'delivery' );
    return $self->eventSystem->control->emit(
        Replay::Message::Report::PurgedSummary->new( $idkey->marshall ) )
      if ( $part eq 'summary' );
    return $self->eventSystem->control->emit(
        Replay::Message::Report::PurgedGlobSummary->new( $idkey->marshall ) )
      if ( $part eq 'globsummary' );
}

sub notify_new {
    my ( $self, $idkey, $part ) = @_;
    $self->notify_new_report( $idkey, $part );
    $self->notify_new_control( $idkey, $part );
}

sub notify_new_generic {
    my ( $self, $channel, $idkey, $part ) = @_;
    return $channel->emit(
        Replay::Message::Report::NewDelivery->new( $idkey->marshall ) )
      if ( $part eq 'delivery' );
    return $channel->emit(
        Replay::Message::Report::NewSummary->new( $idkey->marshall ) )
      if ( $part eq 'summary' );
    return $channel->emit(
        Replay::Message::Report::NewGlobSummary->new( $idkey->marshall ) )
      if ( $part eq 'globsummary' );
}

sub notify_new_report {
    my ( $self, $idkey, $part ) = @_;
    $self->notify_new_generic( $self->eventSystem->report, $idkey, $part );
}

sub notify_new_control {
    my ( $self, $idkey, $part ) = @_;
    $self->notify_new_generic( $self->eventSystem->control, $idkey, $part );

}

sub delete_latest {
    my ( $self, $idkey, $part ) = @_;
    $self->delete_latest_revision($idkey);
    $self->notify_purge( $idkey, $part );
}

sub update {
    my ( $self, $part, $idkey, @state ) = @_;
    my $rule = $self->rule($idkey);
    return unless $rule->can($part);
    return $self->delete_latest( $idkey, $part )
      if 0 == scalar @state && defined $self->current($idkey);
    $self->store( $idkey, $rule->can($part)->( $rule, @state ) );
    $self->notify_new( $idkey, $part );
}

# store a new
sub update_delivery {
    my ( $self, $idkey, @state ) = @_;
    $self->update( 'delivery', $idkey, @state );
}

sub update_summary {
    my ( $self, $idkey, @state ) = @_;
    $self->update( 'summary', $idkey->summary, @state );
}

sub update_globsummary {
    my ( $self, $idkey, @state ) = @_;
    $self->update( 'globsummary', $idkey->globsummary, @state );
}

#report on a key
sub delivery {    #get the named document latest version
    my ( $self, $idkey ) = @_;
    return $self->do_retrieve( $idkey->delivery );
}

# reports on a windows and a key
sub summary {     #
    my ( $self, $idkey ) = @_;
    return $self->do_retrieve( $idkey->summary );
}

# reports all windows for a rule version
sub globsummary {
    my ( $self, $idkey ) = @_;
    return $self->do_retrieve( $idkey->globsummary );
}

#report on a key
sub delivery_data {    #get the named document latest version
    my ( $self, $idkey ) = @_;
    return $self->do_retrieve( $idkey->delivery, 1 );
}

# reports on a windows and a key
sub summary_data {     #
    my ( $self, $idkey ) = @_;
    return $self->do_retrieve( $idkey->summary, 1 );
}

# reports all windows for a rule version
sub globsummary_data {
    my ( $self, $idkey ) = @_;
    return $self->do_retrieve( $idkey->globsummary, 1 );
}

sub do_retrieve {
    my ( $self, $idkey, $structured ) = @_;
    my $result = $self->retrieve( $idkey, $structured );
    confess "retrieve in storage engine implimentation must return hash"
      unless 'HASH' eq ref $result;
    return $result if $result->{EMPTY};
    if ($structured) {
        confess
"retrieve in storage engine implimentation must have DATA key for structured"
          unless exists $result->{DATA};
    }
    else {
        confess
"retrieve in storage engine implimentation must have FORMATTED key for unstructured"
          unless exists $result->{FORMATTED};
    }
    return $result;
}

# get the revsion that is returning
sub revision {
    my ( $self, $idkey ) = @_;
    confess "This isn't an idkey"
      unless UNIVERSAL::isa( $idkey, 'Replay::IdKey' );
    return $idkey->revision if $idkey->has_revision;
    return $self->current($idkey);
}

sub freeze {
    my ( $self, $idkey ) = @_;
    return $self->eventSystem->control->emit(
        Replay::Message::Report::Freeze->new( $idkey->marshall ) );
}

sub copydomain {
    my ( $self, $idkey ) = @_;
    return $self->eventSystem->control->emit(
        Replay::Message::Report::CopyDomain->new( $idkey->marshall ) );
}

sub checkpoint {
    my ( $self, $idkey ) = @_;
    return $self->delay_to_do_once(
        $idkey->hash . 'Reducable',
        sub {
            $self->eventSystem->control->emit(
                Replay::Message::Report::Checkpoint->new( $idkey->marshall ) );
        }
    );
}

sub delay_to_do_once {
    my ( $self, $name, $code ) = @_;
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

=head1 REQUIRED ROLE IMPLIMENTATION METHODS

All role consumers must impliment the following

=head2 retrieve - get report

retrieve($key, $structured)

if $structured is true, return the data structure of the report

otherwise return the formatted version

if no report available, return empty

=head2 store - update the report

store($key, $data, [$formatted])

Overwrite the current version of the report with the new data.

formatted is optional - some reports don't have a formatted output for a particular data key

Data must be an array reference

if the list of data is empty, behavior is to set this report as having no current revision at all 

=head2 freeze - add atom

freeze($key)

if the revision is indicated but not the current, do nothing. otherwise...

Copy the current report to a new revision number, and make the new revision the current

return the key of the frozen revision

=head2 delivery_keys - retrieve a list of current keys within a window

delivery_keys($key)

This is used for the list IdKeys to use to retrieve the data used for summary report generation

=head2 summary_keys - retrieve a list of current windows within a rule-version

summary_keys($key)

This is used for the list IdKeys to use to retrieve the data used for globsummary report generation

=head1 REPORT ENGINE INTERFACE

The utilizers of report engine roles can use these API points

if revision is not specified, latest is assumed
if resulting revision is not available, nothing is returned

=head2 delivery(idkey)

returns the formatted report

=head2 summary(idkey)

returns the formatted report

=head2 globsummary(idkey)

returns the formatted report

=head2 delivery_data(idkey)

returns the structured report data for the delivery (key specific level)

=head2 summary_data(idkey)

returns the structured report data for the summary (all in window level)

=head2 globsummary_data(idkey)

returns the structured report data for the summary (all in rule-version)

=head2 update_delivery(idkey)

uses the data from the storage engine to format the key report

=head2 update_summary(idkey)

uses the data from the storage engine to format the summary report

=head2 update_globsummary(idkey)

uses the data from the storage engine to format the rule-version report

=head2 freeze(idkey)

locks down the latest revision so it can be retrieved forever

=head2 copydomain(olddomain, newdomain)

using copy-on-modify logic, make another domain of reports available

=head2 checkpoint(attimefactor)

checkpoint for easy reversion (like commit into a source control) the state of the
report system when the specified time factor is reached.

=head1 DATA TYPES

 types:
 - idkey:
  { name: string
  , version: string
  , window: string
  , key: string
  , revision: integer
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
  - Replay::Message::Report::NewDelivery - there is a new key level report available;
  - Replay::Message::Report::NewSummary - there is a new window level report available;
  - Replay::Message::Report::NewGlobSummary - there is a new rule-version level report available;
  - Replay::Message::Report::Freeze - A report was frozen
  - Replay::Message::Report::CopyDomain - Copy domain complete
  - Replay::Message::Report::Checkpoint - Checkpoint established
  - Replay::Message::Report::PurgedDelivery - a key level report is now empty
  - Replay::Message::Report::PurgedSummary - a window level report is now empty
  - Replay::Message::Report::PurgedGlobSummary - a rule-version level report is now empty

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

