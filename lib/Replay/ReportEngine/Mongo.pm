package Replay::ReportEngine::Mongo;

use Moose;
use Scalar::Util qw/blessed/;
use Replay::IdKey;
use Carp qw/croak carp cluck/;
use MongoDB;
use MongoDB::OID;

with(qw(Replay::Role::ReportEngine Replay::Role::MongoDB));
our $VERSION = q(0.03);

has '+mode' => ( default => 'Mongo' );

sub _build_mongo {
    my ($self) = @_;
    my $db = MongoDB::MongoClient->new();
    $db->authenticate($self->dbauthdb, $self->dbuser, $self->dbpass);
    return $db;
}

sub _build_dbpass {
    my $self = shift;
    return $self->config->{ReportEngine}{Pass};
}

sub _build_dbuser {
    my $self = shift;
    return $self->config->{ReportEngine}{User};
}

sub _build_dbauthdb {
    my $self = shift;
    return $self->config->{ReportEngine}{AuthDB} || 'admin';
}

sub _build_dbname {
    my $self = shift;
    return $self->config->{ReportEngine}{Name}
        || $self->config->{stage} . "-report-" . '-replay';
}

sub _build_db {
    my ($self) = @_;
    my $config = $self->config;
    my $db     = $self->mongo->get_database($self->dbname);
    return $db;
}

# does the work of actually getting a report from the DB
# returns { DATA => <reference>, FORMATTED => <scalar> }
sub retrieve {
    my ($self, $idkey, $structured) = @_;

    my $revision = $self->revision($idkey) || 0;
    my $keysought = $structured ? 'DATA' : 'FORMATTED';
    my $r = $self->collection($idkey)
        ->find_one({ $self->idkey_where_doc($idkey), REVISION => $revision, },
        { $keysought => 1 });
    return { EMPTY => 1 } unless defined $r && exists $r->{$keysought};
    delete $r->{_id};
    $r->{EMPTY} = 0;
    return $r;
}

sub latest {
    my ($self, $idkey) = @_;
    my $result
        = $self->collection($idkey)
        ->find_one(
        { idkey => $idkey->cubby, NEXT_REVISION => { q/$/ . 'exists' => 1 }, },
        { CURRENT_REVISION => 1, NEXT_REVISION => 1, });
    return $result->{CURRENT_REVISION} || $result->{NEXT_REVISION} || 0;
}

sub delete_latest_revision {
    my ($self, $idkey) = @_;
    my $current = $self->current($idkey);

    # if current is a thing, we need to remove the current version note
    if (defined $current) {
        $self->collection($idkey)->update(
            { $self->idkey_where_doc($idkey), CURRENT_REVISION => $current, },
            { q/$/ . 'unset' => { CURRENT_REVISION => undef }, },
            { upsert => 0, multiple => 0 },
        );
    }
    if ($self->latest($idkey) == 0) {

        # if latest is zero we never froze, just nuke the whole report status as noise
        $self->collection($idkey)->remove({ $self->idkey_where_doc($idkey) });
    }
    else {
        # if latest is not zero we did freeze, just delete the report itself
        $self->collection($idkey)
            ->remove(
            { idkey => $idkey->cubby, NEXT_REVISION => { q/$/ . 'exists' => 0 }, },
            );
    }
    return;
}

#Api
sub store {
    my ($self, $idkey, $reportdata, $formatted) = @_;
    confess
        "first return value from delivery/summary/globsummary function does not appear to be an array ref"
        unless 'ARRAY' eq ref $reportdata;
    my $revision = $self->revision($idkey) || 0;
    return $self->delete_latest_revision($idkey)
        unless scalar @{$reportdata} || defined $formatted;

    # this one is the DATA HOLDING document
    my $r = $self->collection($idkey)->update(
        { idkey => $idkey->cubby, REVISION => $revision },
        {   q^$^
                . 'set' => {
                (defined $formatted    ? (FORMATTED => $formatted)  : ()),
                (scalar @{$reportdata} ? (DATA      => $reportdata) : ()),
                },
            q^$^
                . 'setOnInsert' => {
                idkey    => $idkey->cubby,
                REVISION => $revision,
                IdKey    => $idkey->marshall
                }
        },
        { upsert => 1, multiple => 0 },
    );

    # this one is the REVISION STATE document
    $self->collection($idkey)->update(
        { idkey => $idkey->cubby, NEXT_REVISION => { q/$/ . 'exists' => 1 }, },
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
    my ($self, $idkey) = @_;
    my @r = map {
        Replay::IdKey->new(
            name     => $_->{IdKey}->{name},
            version  => $_->{IdKey}->{version},
            window   => $_->{IdKey}->{window},
            key      => $_->{IdKey}->{key},
            revision => $_->{CURRENT_REVISION},
            )
        } $self->collection($idkey)->find(
        {   'IdKey.name'     => $idkey->name . '',
            'IdKey.version'  => $idkey->version . '',
            'IdKey.window'   => $idkey->window . '',
            'IdKey.key'      => { q/$/ . 'exists' => 1 },
            CURRENT_REVISION => { q/$/ . 'exists' => 1 }
        },
        { IdKey => 1, CURRENT_REVISION => 1 }
        )->all;
    return @r;
}

#Api
sub summary_keys {
    my ($self, $idkey) = @_;
    return map {
        Replay::IdKey->new(
            name     => $_->{IdKey}->{name},
            version  => $_->{IdKey}->{version},
            window   => $_->{IdKey}->{window},
            revision => $_->{CURRENT_REVISION},
            )
        } $self->collection($idkey)->find(
        {   'IdKey.name'     => $idkey->name . '',
            'IdKey.version'  => $idkey->version . '',
            'IdKey.window'   => { q/$/ . 'exists' => 1 },
            'IdKey.key'      => { q/$/ . 'exists' => 0 },
            CURRENT_REVISION => { q/$/ . 'exists' => 1 }
        },
        { IdKey => 1, CURRENT_REVISION => 1 }
        )->all;
}

sub idkey_where_doc {
    my ($self, $idkey) = @_;
    return 'IdKey.name' => $idkey->name . '',
        'IdKey.version' => $idkey->version . '',
        'IdKey.window' =>
        ($idkey->has_window ? ($idkey->window . '') : ({ q/$/ . 'exists' => 0 })),
        'IdKey.key' =>
        ($idkey->has_key ? ($idkey->key . '') : ({ q/$/ . 'exists' => 0 })),
        ;
}

#Api
sub current {
    my ($self, $idkey) = @_;
    return (
        $self->collection($idkey)->find_one(
            {   $self->idkey_where_doc($idkey),
                CURRENT_REVISION => { q/$/ . 'exists' => 1 }
            },
            { CURRENT_REVISION => 1 }
            )
            || {}
    )->{CURRENT_REVISION};
}

# get a report and keep a copy
# ie invoice
sub freeze_delivery {
    my ($self, $idkey) = @_;
    return $self->freeze($idkey->delivery);
}

sub freeze_summary {
    my ($self, $idkey) = @_;
    return $self->freeze($idkey->summary);
}

sub freeze_globsummary {
    my ($self, $idkey) = @_;
    return $self->freeze($idkey->globsummary);
}

sub freeze {
    confess "unimplimented";
    my ($self, $idkey) = @_;
    $idkey->revision();
    my $newrevision = $self->revision($idkey) + 1;
    $self->collection($idkey)->update(
        { idkey => $idkey->cubby, NEXT_REVISION => { q/$/ . 'exists' => 1 }, },
        {   q/$/
                . 'set' =>
                { CURRENT_REVISION => $newrevision, NEXT_REVISION => $newrevision, },
            q^$^ . 'setOnInsert' => { idkey => $idkey->cubby, IdKey => $idkey->marshall },
        },
        { upsert => 1, multiple => 0 },
    );

    # this should copy the current report to a new one, and increment CURRENT.
}

1;

__END__

=pod

=head1 NAME

Replay::ReportEngine::Filesystem - report implimentation for filesystem - testing only

=head1 VERSION

Version 0.01

=head1 SYNOPSIS

Replay::ReportEngine::Filesystem->new( ruleSoruce => $rs, eventSystem => $es, config => {...} );

Stores the entire storage partition in package memory space.  Anybody in
this process can access it as if it is a remote storage solution... only
faster.

=head1 SUBROUTINES/METHODS

=head2 _build_mongo

the mongo connection

=head2 _build_dbpass

the db password

=head2 _build_dbuser

the db username

=head2 _build_dbauthdb

the authentication db within the mongo server

=head2 _build_dbname

the name of the db we'll be readding/writing with

=head2 _build_db

the handle to the db

=head2 retrieve( idkey, isStructured? )

return the indicated revision, in the indicated form, as a hashref which
looks like one of these.  isStructured selects the DATA instead of the 
FORMATTED

{ EMPTY => 0, DATA => [] }
{ EMPTY => 0, FORMATTED => [] }
{ EMPTY => 1 }

=head2 latest( idkey )

return the latest revision we can write to for an idkey

=head2 delete_latest_revision( idkey )

delete the latest revision, making it entirely unavailable

=head2 store( idkey, [data], $formatted )

store this data array and maybe this formatted data at this idkey in the 
latest revision (the only writable revision)

=head2 delivery_keys( idkey )

return an enumeration of all of the keys within a window which have current 
versions. used when creating summaries. not all of these keys necessarily 
have structured information available!

=head2 summary_keys( idkey )

return an enumeration of all of the keys within a rule-version which have 
current versions. used when creating summaries. not all of these keys 
necessarily have structured information available!

=head2 idkey_where_doc( idkey )

returns the basic where or query block for retrieving a document

=head2 current( idkey )

returns the current version for a report (if it exists) or empty/undef 
otherwise

=head2 freeze_delivery( idkey )

initiate the freezing of a delivery-content level summary

=head2 freeze_summary( idkey )

initiate the freezing of a summary-content level summary

=head2 freeze_globsummary( idkey )

initiate the freezing of a global-summary-content level summary

=head2 freeze( idkey )

initiate the freezing at the level indicated in the idkey

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
