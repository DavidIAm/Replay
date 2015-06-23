package Replay::ReportEngine::Filesystem;

use Moose;
use Scalar::Util qw/blessed/;
use Replay::IdKey;
use Carp qw/croak carp cluck/;
use JSON qw/to_json/;
use File::Spec::Functions;
use File::Path qw/mkpath/;
use File::Slurp qw/read_file/;
use Readonly;
use Storable qw/store_fd/;
use IO::Dir;

with 'Replay::BaseReportEngine';

our $VERSION = q(0.03);

Readonly my $CURRENTFILE  => 'CURRENT';
Readonly my $WRITABLEFILE => 'WRITABLE';

my $store = {};

sub BUILD {
    my $self = shift;
    mkpath $self->config->{ReportEngine}->{reportFilesystemRoot};
    use Data::Dumper;
    confess "no report filesystem root (" . Dumper($self->config). ")"
        unless -d $self->config->{ReportEngine}->{reportFilesystemRoot};
}

sub retrieve {
    my ($self, $idkey, $structured) = @_;
    my $directory = $self->directory($idkey);
    my $revision  = $self->revision($idkey);
    return { EMPTY => 1 } unless defined $revision;    # CASE: NO CURRENT REPORT
    if ($structured) {
        my $dfile = $self->filename_data($directory, $self->revision($idkey));
        return { EMPTY => 0, DATA => Storable::retrieve $dfile } if -f $dfile;
        return { EMPTY => 1 };
    }
    my $ffile = $self->filename($directory, $self->revision($idkey));
    return { EMPTY => 0, FORMATTED => read_file($ffile) } if -f $ffile;
    return { EMPTY => 1 };
}

sub writable_revision_path {
    my ($self, $directory) = @_;
    return catfile($directory, $WRITABLEFILE);
}

sub current_revision_path {
    my ($self, $directory) = @_;
    return catfile($directory, $CURRENTFILE);
}

sub writable_revision {
    my ($self, $directory) = @_;
    return 0 unless -d $directory;
    my $wfile = $self->writable_revision_path($directory);
    return 0 unless (-f $wfile);
    return read_file($wfile) || 0;
}

sub current_revision {
    my ($self, $directory) = @_;
    return undef unless -d $directory;
    my $vfile = $self->current_revision_path($directory);
    return undef unless (-f $vfile);
    return read_file($vfile) || 0;
}

sub current {
    my ($self, $idkey) = @_;
    return $self->current_revision($self->directory($idkey));
}

# retrieves all the keys that point to valid deliveries in the current window
sub subdirs {
    my ($self, $parentDir) = @_;
    my @subdirs;
    my $dir = IO::Dir->new($parentDir);
    if (defined $dir) {
        my $entry;
        while (defined($entry = $dir->read)) {
            my $path = catdir $parentDir, $entry;
            next unless -d $path;
            next if $entry =~ /^\./;
            push @subdirs, $entry;
        }
    }
    return @subdirs;
}

# filters a list of directories by those which contain a CURRENT file
sub current_subdirs {
    my ($self, $parentDir) = @_;
    return
        grep { -f catfile $parentDir, $_, $CURRENTFILE }
        $self->subdirs($parentDir);
}

# retrieves all the keys that point to valid summaries in the current
# rule-version
sub delivery_keys {
    my ($self, $sumkey) = @_;
    my $parentDir = $self->directory($sumkey);
    map {
        Replay::IdKey->new(
            name     => $sumkey->name,
            version  => $sumkey->version,
            window   => $sumkey->window,
            key      => $_->[0],
            revision => $_->[1],
            )
        } grep { defined $_->[1] }
        map { [ $_ => $self->current_revision(catdir $parentDir, $_) ] }
        $self->current_subdirs($parentDir);
}

sub summary_keys {
    my ($self, $sumkey) = @_;
    my $parentDir = $self->directory($sumkey);
    map {
        Replay::IdKey->new(
            name     => $sumkey->name,
            version  => $sumkey->version,
            window   => $_->[0],
            revision => $_->[1],
            )
        } grep { defined $_->[1] }
        map { [ $_ => $self->current_revision(catdir $parentDir, $_) ] }
        $self->current_subdirs($parentDir);
}

sub filename_data {
    my ($self, $directory, $revision) = @_;
    return catfile $directory, sprintf 'revision_%05d.data', $revision;
}

sub filename {
    my ($self, $directory, $revision) = @_;
    return catfile $directory, sprintf 'revision_%05d', $revision;
}

sub directory {
    my ($self, $idkey) = @_;
    return catdir(
        $self->config->{ReportEngine}->{Root},
        $idkey->name,
        $idkey->version,
        ($idkey->window ? ($idkey->window) : ()),
        ($idkey->key    ? ($idkey->key)    : ())
    );
}

sub delete_latest_revision {
    my ($self, $idkey) = @_;
    my $directory = $self->directory($idkey);
    $self->lock($directory);
    unlink $self->filename($directory, $self->writable_revision($directory));
    unlink $self->filename_data($directory, $self->writable_revision($directory));
    unlink catfile $directory, $CURRENTFILE;

    # if there was a freeze then the writable revision is greater than zero and
    # we are obligated to keep the directory around. Otherwise, drop it.
    unlink catfile $directory, $WRITABLEFILE
        if $self->writable_revision($directory) == 0;
    rmdir $directory;
    $self->unlock($directory);
    return;
}

sub store {
    my ($self, $part, $idkey, $data, $formatted) = @_;
    confess
        "first return value from delivery/summary/globsummary function does not appear to be an array ref"
        unless 'ARRAY' eq ref $data;
    my $directory = $self->directory($idkey);
    return $self->delete_latest_revision($idkey) unless scalar @{$data};
    mkpath $directory unless -d $directory;
    $self->lock($directory);

    # TODO: make this thread safe writes with temp name and renames
    {
        my $wfile = $self->writable_revision_path($directory);
        unless (-f $wfile) {
            my $wh = IO::File->new($wfile, 'w');
            print $wh $self->writable_revision($directory);
        }
    }

    # TODO: make this thread safe writes with temp name and renames
    {
        my $vfile = $self->current_revision_path($directory);
        unless (-f $vfile) {
            my $vh = IO::File->new($vfile, 'w');
            print $vh $self->writable_revision($directory);
        }
    }

    # TODO: make this thread safe writes with temp name and renames
    {
        my $datafilename
            = $self->filename_data($directory, $self->writable_revision($directory));
        my $dfh = IO::File->new($datafilename, 'w');
        store_fd $data, $dfh or confess "NO DATA $$ $? $! PRINT " . to_json $data;
    }

    if (defined $formatted) {

        # TODO: make this thread safe writes with temp name and renames
        my $filename
            = $self->filename($directory, $self->writable_revision($directory));
        my $fh = IO::File->new($filename, 'w');
        print $fh $formatted or confess "NO DATA $$ $? $! PRINT " . $formatted;
    }

    $self->unlock($directory);
}

sub lock {
    my ($self, $directory) = @_;
}

sub unlock {
    my ($self, $directory) = @_;
}

# State transition = add new atom to inbox

sub freeze {
    confess "unimplimented";
    my ($self, $part, $idkey) = @_;

    # this should copy the current report to a new one, and increment CURRENT
    # AND WRITABLE.
    my $directory = $self->directory($idkey);

    $self->lock($directory);

    my $old_revision = $self->current_revision($directory);
    my $new_revision = $old_revision + 1;

    my $vfile = $self->current_revision_path($directory);
    unless (-f $vfile) {
        my $vh = IO::File->new($vfile, 'w');
        print $vh $new_revision;
    }
    my $wfile = $self->writable_revision_path($directory);
    unless (-f $wfile) {
        my $wh = IO::File->new($vfile, 'w');
        print $wh $new_revision;
    }

    my $oldkey = Replay::IdKey->new(
        revision => $old_revision,
        rule     => $idkey->rule,
        version  => $idkey->version,
        ($idkey->window ? (window => $idkey->window) : ()),
        ($idkey->key    ? (key    => $idkey->key)    : ()),
    );

    $self->store(
        $part, $idkey,
        $self->retrieve($oldkey, 1)->{DATA},
        $self->retrieve($oldkey)->{FORMATTED}
    );

    $self->unlock($directory);
}

1;

__END__

=pod

=head1 NAME

Replay::ReportEngine::Filesystem - report implimentation for filesystem - testing only

=head1 VERSION

Version 0.03

=head1 SYNOPSIS

Replay::ReportEngine::Filesystem->new( 
        config      => 
        { ReportEngine => { 
          Mode => FileSystem, 
          Root => $storedir, 
          },
        ruleSource  => $self->ruleSource,
        eventSystem => $self->eventSystem,
    );

Initializes the Filesystem report engine.

=head1 DESCRIPTION

Data structure follows the format of the idkey.

The hierarchy names are joined together to form a path.

.../ROOT/RULENAME/VERSIONNUM/WINDOWNAME/KEYNAME/...

if a key or window isn't relevant (for summaries and globsummary) the directory is merely not present.

Files within a directory, and what they mean

WRITABLE - contains a number, the revision number of the current version for writing.

if there is no WRITABLE, this layer of report has never had data in it.

CURRENT - contains a number, the revision number of the latest existing report

if there is no CURRENT, the report is 404, not available.

revision_##### - contains the 'formatted' report - in whatever format programmer desires.

revision_#####.data - contains the 'data' part of report - in storable format for easy reading by perl


a 'purge' happens when a report or summary returns empty list, indicating 'no state to report'. The system will remove the current revision file, and the CURRENT file to indicate there is no report available at this location any longer.

a 'freeze' request acts on the latest revision.  the writable revision is moved up one and the previously latest version is copied to it. The frozen version will never be removed.

=head1 METHODS

=head2 BUILD

return the path for the writable revision file in this directory

=head2 retrieve(idkey, structured)

structured is boolean

return the raw data if structured is set

otherwise return the formatted form of the report

=head2 writable_revision_path(directory)

return the path for the writable revision file in this directory

=head2 current_revision_path(directory)

return the path for the current revision file in this directory

=head2 writable_revision(directory)

return the writable revision appropriate for this directory

=head2 current_revision(directory)

return the current revision appropriate for this directory

=head2 current(idkey)

return the current revision appropriate for this key

=head2 subdirs(directory)

return the list of keys to subdirectories that exist in this directory

=head2 current_subdirs(directory)

return the list of keys to subdirectories that have current values for this directory

=head2 delivery_keys(idkey)

return the list of keys that have current values for this window location

=head2 summary_keys(idkey)

return the list of windows that have current values for this rule-version location

=head2 filename_data(directory, revision)

return the data filename for this directory and revision

=head2 filename(directory, revision)

return the formatted filename for this directory and revision

=head2 directory(idkey)

return the directory appropriate for this key

=head2 delete_latest_revision(idkey)

Remove the current report for this location

=head2 store(part=(delivery|summary|globsummary), idkey, data=[...], formatted)

part is one of 'delivery', 'summary', 'globsummary'

data is an array reference

save to our filesystem, this data and optionally the formatted information.

if data is empty, purge the indicated storage slot.

if it isn't, write the data to the data file and formatted to the formatted file

=head2 lock(directory)

lock so other workers don't modify this file path

=head2 unlock(directory)

unlock so other workers can modify this file path

=head2 freeze($idkey)

enact the freeze logic for filesystem

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
