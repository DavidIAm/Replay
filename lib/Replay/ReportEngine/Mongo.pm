package Replay::ReportEngine::Mongo;

use Moose;
use Scalar::Util qw/blessed/;
use Replay::IdKey;
use Carp qw/croak carp cluck/;
use MongoDB;
use MongoDB::OID;

our $VERSION = q(0.03);

has 'Name' =>
    ( is => 'ro', isa => 'Str', builder => '_build_name', lazy => 1, );

has 'thisConfig' => ( is => 'ro', isa => 'HashRef', required => 1, );

my $store = {};
with( 'Replay::Role::MongoDB', 'Replay::Role::ReportEngine' );

has '+mode' => ( default => 'Mongo' );

sub _build_name {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my ($self) = @_;
    return $self->thisConfig->{Name};
}

sub _build_dbpass {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my $self = shift;
    return $self->thisConfig->{Pass};
}

sub _build_dbuser {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my $self = shift;
    return $self->thisConfig->{User};
}

sub _build_dbauthdb {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my $self = shift;
    return $self->thisConfig->{AuthDB} || 'admin';
}

sub _build_dbname {      ## no critic (ProhibitUnusedPrivateSubroutines)
    my $self = shift;
    return $self->thisConfig->{Name}
        || $self->thisConfig->{stage} . '-report-' . '-replay';
}

sub _build_db {          ## no critic (ProhibitUnusedPrivateSubroutines)
    my ($self) = @_;
    my $db = $self->mongo->get_database( $self->dbname );
    return $db;
}

# does the work of actually getting a report from the DB
# returns { DATA => <reference>, FORMATTED => <scalar> }
sub retrieve {
    my ( $self, $idkey, $structured ) = @_;

    my $revision = $self->revision($idkey) || 0;
    my $idkey_where = { $self->idkey_where_doc($idkey) };
    $idkey_where->{REVISION} = $revision;
    my $r
        = $self->collection($idkey)
        ->find_one( $idkey_where,
        { ( $structured ? ( DATA => 1 ) : ( FORMATTED => 1 ) ) } );
    if ( !defined $r ) {
        return { EMPTY => 1 };
    }
    delete $r->{_id};
    $r->{EMPTY} = 0;
    $r->{TYPE}  = 'text/plain';
    return $r;
}

sub latest {
    my ( $self, $idkey ) = @_;
    my $result = $self->collection($idkey)->find_one(
        {   idkey         => $idkey->cubby,
            NEXT_REVISION => { q/$/ . 'exists' => 1 },
        },
        { CURRENT_REVISION => 1, NEXT_REVISION => 1, }
    );
    return $result->{CURRENT_REVISION} || $result->{NEXT_REVISION} || 0;
}

sub delete_latest_revision {
    my ( $self, $idkey ) = @_;
    my $current = $self->current($idkey);

    # if current is a thing, we need to remove the current version note
    if ( defined $current ) {
        my $idkey_where = { $self->idkey_where_doc($idkey) };
        $idkey_where->{CURRENT_REVISION} = $current;
        $self->collection($idkey)->update_many(
            $idkey_where,
            { q/$/ . 'unset' => { CURRENT_REVISION => undef }, },
            { upsert => 0, multiple => 0 },
        );
    }
    if ( $self->latest($idkey) == 0 ) {

# if latest is zero we never froze, just nuke the whole report status as noise
        $self->collection($idkey)
            ->delete_one( { $self->idkey_where_doc($idkey) } );
    }
    else {
        # if latest is not zero we did freeze, just delete the report itself
        $self->collection($idkey)->delete_one(
            {   idkey         => $idkey->cubby,
                NEXT_REVISION => { q/$/ . 'exists' => 0 },
            },
        );
    }
    return;
}

#Api
sub store {
    my ( $self, $idkey, $reportdata, $formatted ) = @_;
    confess 'WHUT DATA' if scalar @{$reportdata} && !defined $reportdata->[0];
    my $revision = $self->revision($idkey) || 0;
    my $r = $self->collection($idkey)->update_many(
        { idkey => $idkey->cubby, REVISION => $revision },
        {   q^$^ . 'set' => { FORMATTED => $formatted, DATA => $reportdata, },
            q^$^
                . 'setOnInsert' => {
                idkey    => $idkey->cubby,
                REVISION => $revision,
                IdKey    => $idkey->marshall
                }
        },
        { upsert => 1, multiple => 0 },
    );
    $self->collection($idkey)->update_many(
        {   idkey         => $idkey->cubby,
            NEXT_REVISION => { q/$/ . 'exists' => 1 },
        },
        {   q^$^
                . 'setOnInsert' => {
                CURRENT_REVISION => $revision,
                NEXT_REVISION    => $revision,
                idkey            => $idkey->cubby,
                IdKey            => $idkey->marshall,
                },
        },
        { upsert => 1, multiple => 0 },
    );

    super();
    return $r;
}

#Api
sub delivery_keys {
    my ( $self, $idkey ) = @_;
    my @r = map {
        Replay::IdKey->new(
            name     => $_->{IdKey}->{name},
            version  => $_->{IdKey}->{version},
            window   => $_->{IdKey}->{window},
            key      => $_->{IdKey}->{key},
            revision => $_->{CURRENT_REVISION},
            )
        } $self->collection($idkey)->find(
        {   'IdKey.name'     => $idkey->name . q{},
            'IdKey.version'  => $idkey->version . q{},
            'IdKey.window'   => $idkey->window . q{},
            'IdKey.key'      => { q/$/ . 'exists' => 1 },
            CURRENT_REVISION => { q/$/ . 'exists' => 1 }
        },
        { IdKey => 1, CURRENT_REVISION => 1 }
        )->all;
    return @r;
}

#Api
sub summary_keys {
    my ( $self, $idkey ) = @_;
    return map {
        Replay::IdKey->new(
            name     => $_->{IdKey}->{name},
            version  => $_->{IdKey}->{version},
            window   => $_->{IdKey}->{window},
            revision => $_->{CURRENT_REVISION},
            )
        } $self->collection($idkey)->find(
        {   'IdKey.name'     => $idkey->name . q{},
            'IdKey.version'  => $idkey->version . q{},
            'IdKey.window'   => { q/$/ . 'exists' => 1 },
            'IdKey.key'      => { q/$/ . 'exists' => 0 },
            CURRENT_REVISION => { q/$/ . 'exists' => 1 }
        },
        { IdKey => 1, CURRENT_REVISION => 1 }
        )->all;
}

sub idkey_where_doc {
    my ( $self, $idkey ) = @_;
    return 'IdKey.name' => $idkey->name . q{},
        'IdKey.version' => $idkey->version . q{},
        'IdKey.window' => ( $idkey->has_window ? ( $idkey->window . q{} )
        : ( { q/$/ . 'exists' => 0 } ) ),
        'IdKey.key' => ( $idkey->has_key ? ( $idkey->key . q{} )
        : ( { q/$/ . 'exists' => 0 } ) ),
        ;
}

#Api
sub current {
    my ( $self, $idkey ) = @_;
    my $idkey_where = { $self->idkey_where_doc($idkey) };
    $idkey_where->{CURRENT_REVISION} = { q/$/ . 'exists' => 1 };
    return ( $self->collection($idkey)
            ->find_one( $idkey_where, { CURRENT_REVISION => 1 } ) || {} )
        ->{CURRENT_REVISION};
}

# get a report and keep a copy
# ie invoice
sub freeze_delivery {
    my ( $self, $idkey ) = @_;
    return $self->freeze( $idkey->delivery );
}

sub freeze_summary {
    my ( $self, $idkey ) = @_;
    return $self->freeze( $idkey->summary );
}

sub freeze_globsummary {
    my ( $self, $idkey ) = @_;
    return $self->freeze( $idkey->globsummary );
}

sub freeze {
    my ( $self, $idkey ) = @_;
    confess 'unimplemented' if $idkey ne 'what it will never equal';

    $idkey->revision();
    my $newrevision = $self->revision($idkey) + 1;
    $self->collection($idkey)->update_many(
        {   idkey         => $idkey->cubby,
            NEXT_REVISION => { q/$/ . 'exists' => 1 },
        },
        {   q/$/
                . 'set' => {
                CURRENT_REVISION => $newrevision,
                NEXT_REVISION    => $newrevision,
                },
            q^$^
                . 'setOnInsert' =>
                { idkey => $idkey->cubby, IdKey => $idkey->marshall },
        },
        { upsert => 1, multiple => 0 },
    );

    # this should copy the current report to a new one, and increment CURRENT.
    return;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 NAME

Replay::ReportEngine::Mongo - report implementation for mongodb


=head1 VERSION

Version 0.01

=head1 SYNOPSIS

Replay::ReportEngine::Mongo->new( ruleSource => $rs, eventSystem => $es, config => {...} );

Stores the entire report storage block in a mongo database.  

=head1 DESCRIPTION

Provides report storage and retrieval functionality through a Mongo database

=head1 SUBROUTINES/METHODS

=head2 retrieve - get document

=head2 absorb - add atom

=head2 checkout - lock and return document

=head2 revert - revert and unlock document

=head2 checkin - update and unlock document

=head2 window_all - get documents for a particular window

=head1 DIAGNOSTICS

No specific diagnostic capabilities programmed

=head1 DEPENDENCIES

You'll need to have a mongo client and an available mongo server 
in order to use this.

=head1 INCOMPATIBILITIES

Probably won't work well with old versions of mongo.

=head1 CONFIGURATION AND ENVIRONMENT

You will need to have a mongo database available

It is configured with  fragment like:

            {   Mode      => 'Mongo',
                User => 'replayuser',
                Name      => 'MongoTest',
                Pass => 'replaypass'
            }

=head1 AUTHOR

David Ihnen, C<< <davidihnen at gmail.com> >>

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
