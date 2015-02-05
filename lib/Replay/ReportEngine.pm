package Replay::ReportEngine;

use Replay::BaseReportEngine;
use Moose;
use Try::Tiny;
use Carp qw/croak/;
use English qw/-no_match_vars/;

our $VERSION = '0.03';

has config => (is => 'ro', isa => 'HashRef[Item]', required => 1,);
has engine => (
    is      => 'ro',
    isa     => 'Replay::BaseReportEngine',
    builder => '_build_engine',
    lazy    => 1,
);
has mode => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
    builder  => '_build_mode',
    lazy     => 1,
);
has ruleSource  => (is => 'ro', isa => 'Replay::RuleSource',  required => 1,);
has eventSystem => (is => 'ro', isa => 'Replay::EventSystem', required => 1,);
has storageEngine =>
    (is => 'ro', isa => 'Replay::StorageEngine', required => 1,);

# Delegate the api points
sub delivery {
    my ($self, $idkey) = @_;
    return $self->engine->delivery($idkey->delivery);
}
sub summary {
    my ($self, $idkey) = @_;
    return $self->engine->summary($idkey->summary);
}
sub globsummary {
    my ($self, $idkey) = @_;
    return $self->engine->globsummary($idkey->globsummary);
}
sub update_delivery {
    my ($self, $idkey) = @_;
    return $self->engine->update_delivery($idkey,
        $self->storageEngine->fetch_canonical_state($idkey));
}

sub update_summary {
    my ($self, $idkey) = @_;
    return $self->engine->update_summary($idkey,
        $self->reportEngine->fetch_summary_data($idkey));
}
sub update_globsummary {
    my ($self, $idkey) = @_;
    return $self->engine->update_globsummary($idkey,
        $self->reportEngine->fetch_globsummary_data($idkey));
}

sub freeze {
  confess "unimplimented";
}

sub checkpoint {
  confess "unimplimented";
}

sub _build_engine {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my $self      = shift;
    my $classname = $self->mode;
    return $classname->new(
        config      => $self->config,
        ruleSource  => $self->ruleSource,
        eventSystem => $self->eventSystem,
    );
}

sub _build_mode {      ## no critic (ProhibitUnusedPrivateSubroutines)
    my $self = shift;
    if (not $self->config->{ReportEngine}->{Mode}) {
        croak q(No ReportMode?);
    }
    my $class = 'Replay::ReportEngine::' . $self->config->{ReportEngine}->{Mode};
    try {
        eval "require $class"
            or croak qq(error requiring class $class : ) . $EVAL_ERROR;
    }
    catch {
        confess q(No such report engine mode available )
            . $self->config->{ReportEngine}->{Mode}
            . " --> $_";
    };
    return $class;
}

1;

__END__

=pod

=head1 NAME

Replay::ReportEngine - abstracted interface to the report portion of the Replay system

=head1 VERSION

Version 0.01

=head1 SYNOPSIS

This is the implementation agnostic interface for the report portion of the Replay system.

You can instantiate a ReportEngine object with a list of rules and config

use Replay::ReportEngine;

my $storage = Replay::ReportEngine->new( ruleSource => $ruleSource, config => { ReportEngine => { Mode => 'Memory', awsIdentity } );

=head1 DESCRIPTION

The report data model consists of a series of locations represented by 'idkey' type plus frozen 0revisions.

The ID type has a NAMESPACE series of axis such as 'name', and 'version', but 
could also contain 'domain', 'system', 'worker', 'client', or any other set 
of divisions as suits the application

# how do we coordinate between workers?

When a new canonical state has been stored in the storage engine, when the rule involved 
has a delivery function, the report engine retrieves that state from storage and processes 
it through the delivery function.  The new version is commited to the repo, and a new report 
version event is emitted.

When a new report event is detected, and there is a summary directive
 in the corresponding rule, all of the reports for a particular 
 window are retrieved and passed through the summary directive. 
 The result is commited as a summary for that window.

When a Report Engine Checkpoint event arrives, the report engine will complete 
all in-progress processing of deliveries and subsequent summaries and 
tag the set per the checkpoint identification

When a deliver-and-freeze request arrives, the report engine will collapse all of the 
changes on the specified point from the last freeze into a single change and commit 
the file to the frozen branch

Every report has metadata - the timeblocks used, rule-versions used to process

The report engine exhibits a REST style interface that allows services to retrieve reports and summaries on something like:

=head2 Resources for a key:

GET /reports/DOMAIN/REPORTNAME/VERSION/WINDOW/KEY
302 Location: /reports/DOMAIN/REPORTNAME/VERSION/WINDOW/KEY/latest

GET /reports/DOMAIN/REPORTNAME/VERSION/WINDOW/KEY/latest
302 Location: /reports/DOMAIN/REPORTNAME/VERSION/WINDOW/KEY/REVISION

GET /reports/DOMAIN/REPORTNAME/VERSION/WINDOW/KEY/revisionlist
200 Content-type: application/json
[ 'v20140728': { meta: { ruleversionwindows:[],timeblocks:[] }, frozen_at_time: 12345 }
, 'v20140728': { meta: { ruleversionwindows:[],timeblocks:[] }, updated_time 23456 }
]

GET /reports/DOMAIN/REPORTNAME/VERSION/WINDOW/KEY/REVISION
200 Content-type: TheReportFormat

POST /reports/DOMAIN/REPORTNAME/VERSION/WINDOW/KEY/freeze
302 Location: /reports/DOMAIN/REPORTNAME/VERSION/WINDOW/KEY/NEWFROZENREVISION

=head2 Resources for a window - summary:

GET /reports/DOMAIN/REPORTNAME/VERSION/WINDOW
302 Location: /reports/DOMAIN/REPORTNAME/VERSION/WINDOW/latest

GET /reports/DOMAIN/REPORTNAME/VERSION/WINDOW/REVISION
200 Content-type: TheReportFormat

POST /reports/DOMAIN/REPORTNAME/VERSION/WINDOW/freeze
302 Location: /reports/DOMAIN/REPORTNAME/VERSION/WINDOW/NEWFROZENREVISION

GET /reports/DOMAIN/REPORTNAME/VERSION/WINDOW/revisionlist
200 Content-type: application/json
[ 'v20140728': { meta: { ruleversionwindows:[],timeblocks:[] }, frozen_at_time: 12345 }
, 'v20140728': { meta: { ruleversionwindows:[],timeblocks:[] }, updated_time 23456 }

=head2 Resources for a report - glob summary:

GET /reports/DOMAIN/REPORTNAME/VERSION
302 Location: /reports/DOMAIN/REPORTNAME/VERSION/latest

GET /reports/DOMAIN/REPORTNAME/VERSION/REVISION
200 Content-type: TheReportFormat

POST /reports/DOMAIN/REPORTNAME/VERSION/freeze
302 Location: /reports/DOMAIN/REPORTNAME/VERSION/NEWFROZENREVISION

GET /reports/DOMAIN/REPORTNAME/VERSION/revisionlist
200 Content-type: application/json
[ 'v20140728': { meta: { ruleversionwindows:[],timeblocks:[] }, frozen_at_time: 12345 }
, 'v20140728': { meta: { ruleversionwindows:[],timeblocks:[] }, updated_time 23456 }

=head1 SUBROUTINES/METHODS

=head2 delivery ( domain, report, version, window, key )

delegate to the engine delivery

=head2 summary ( domain, report, version, window )

delegate to the engine summary

=head2 globsummary ( domain, report, version )

delegate to the engine globsummary

=head2 freeze ( domain, report, version, window, revision )
=head2 freeze ( domain, report, version, window )
=head2 freeze ( domain, report, version )

delegate to the engine freeze

=head2 checkpoint ( domain )

delegate to the engine checkpoint

=head2 copydomain ( newdomain, oldcheckpoint )

delegate to the engine copyDomain

=head2 _build_engine

create the appropriate engine

=head2 _build_mode

figure out what mode they're wanting

=head2 window_all(idkey)

see BaseReportEngine window_all

=cut

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

