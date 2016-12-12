package Replay::ReportEngine::Filesystem;

use Moose;
use English qw/ -no_match_vars /;
use Scalar::Util qw/blessed/;
use Replay::IdKey;
use Carp qw/croak carp cluck/;
use JSON qw/to_json/;
use File::Spec::Functions;
use File::Path qw/mkpath/;
use File::MimeInfo::Magic qw/mimetype/;
use File::Slurp qw/read_file/;
use Readonly;
use Cwd 'abs_path';
use Storable qw/store_fd/;
use IO::Dir;

our $VERSION = q(0.03);

Readonly my $CURRENTFILE  => 'CURRENT';
Readonly my $WRITABLEFILE => 'WRITABLE';

has 'Root' =>
    ( is => 'ro', isa => 'Str', builder => '_build_root', lazy => 1, );

has 'Name' =>
    ( is => 'ro', isa => 'Str', builder => '_build_name', lazy => 1, );

has 'thisConfig' => ( is => 'ro', isa => 'HashRef', required => 1, );

with 'Replay::Role::ReportEngine';

has '+mode' => ( default => 'Filesystem' );

my $store = {};

sub _build_name {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my $self = shift;
    return $self->thisConfig->{Name};
}

sub _build_root {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my $self = shift;

    my $directory = abs_path( $self->thisConfig->{Root} );

    if ( !$directory ) {
        my @test = mkpath $self->thisConfig->{Root};
        $directory = shift @test;
    }

    if ( !-d $directory ) {
        confess 'no exist report filesystem Root '
            . to_json $self->thisConfig;
    }

    return $directory;
}

sub retrieve {
    my ( $self, $idkey, $structured ) = @_;
    my $directory = $self->directory($idkey);
    my $revision  = $self->revision($idkey);
    use Data::Dumper;
    return { EMPTY => 1 } if !defined $revision;    # CASE: NO CURRENT REPORT
    if ($structured) {
        my $dfile
            = $self->filename_data( $directory, $self->revision($idkey) );
        return { EMPTY => 0, DATA => Storable::retrieve $dfile, }
            if -f $dfile;
        return { EMPTY => 1 };
    }
    my $ffile = $self->filename( $directory, $self->revision($idkey) );
    return {
        EMPTY     => 0,
        TYPE      => mimetype($ffile),
        FORMATTED => join q{},
        read_file($ffile)
        }
        if -f $ffile;
    return { EMPTY => 1 };
}

sub writable_revision_path {
    my ( $self, $directory ) = @_;
    return catfile( $directory, $WRITABLEFILE );
}

sub current_revision_path {
    my ( $self, $directory ) = @_;
    return catfile( $directory, $CURRENTFILE );
}

sub writable_revision {
    my ( $self, $directory ) = @_;
    return 0 if !-d $directory;
    my $wfile = $self->writable_revision_path($directory);
    return 0 if !-f $wfile;
    return read_file($wfile) || 0;
}

sub current_revision {
    my ( $self, $directory ) = @_;
    if ( !-d $directory ) {
        return undef;    ## no critic (ProhibitExplicitReturnUndef)
    }

    my $vfile = $self->current_revision_path($directory);
    if ( !-f $vfile ) {
        return undef;    ## no critic (ProhibitExplicitReturnUndef)
    }
    return map { chomp && $_ } read_file($vfile);
}

sub current {
    my ( $self, $idkey ) = @_;
    return $self->current_revision( $self->directory($idkey) );
}

# retrieves all the keys that point to valid deliveries in the current window
sub subdirs {
    my ( $self, $parent_dir ) = @_;
    my @subdirs;
    my $dir = IO::Dir->new($parent_dir);
    if ( defined $dir ) {
        my $entry;
        while ( defined( $entry = $dir->read ) ) {
            my $path = catdir $parent_dir, $entry;
            next if !-d $path;
            next if $entry =~ /^[.]/xsm;
            push @subdirs, $entry;
        }
    }
    my @sorted = sort @subdirs;
    return @sorted;
}

# filters a list of directories by those which contain a CURRENT file
sub current_subdirs {
    my ( $self, $parent_dir ) = @_;
    return
        grep { -f catfile $parent_dir, $_, $CURRENTFILE }
        $self->subdirs($parent_dir);
}

# retrieves all the valid keys in the list for the next layer down in the reports
# rule-version-window-key
sub subkeys {
    my ( $self, $key ) = @_;
    carp 'directory is ' . $self->directory($key);
    if ( $key->has_key ) {

        my $dir = IO::Dir->new( $self->directory($key) );

        my @revisions;
        if ( defined $dir ) {
            my $entry;
            while ( defined( $entry = $dir->read ) ) {
                my ($revision) = $entry =~ /revision_(\d+).data/xsm;
                next if !defined $revision;
                push @revisions, $revision;
            }
        }
        return [@revisions];
    }
    else {
        return [ $self->subdirs( $self->directory($key) ) ];
    }
}

# retrieves all the keys that point to valid summaries in the current
# rule-version
sub delivery_keys {
    my ( $self, $sumkey ) = @_;
    my $parent_dir = $self->directory($sumkey);
    return map {
        Replay::IdKey->new(
            name     => $sumkey->name,
            version  => $sumkey->version,
            window   => $sumkey->window,
            key      => $_->[0],
            revision => $_->[1],
            )
        } grep { defined $_->[1] }
        map { [ $_ => $self->current_revision( catdir $parent_dir, $_ ) ] }
        $self->current_subdirs($parent_dir);
}

sub summary_keys {
    my ( $self, $sumkey ) = @_;
    my $parent_dir = $self->directory($sumkey);
    return map {
        Replay::IdKey->new(
            name     => $sumkey->name,
            version  => $sumkey->version,
            window   => $_->[0],
            revision => $_->[1],
            )
        } grep { defined $_->[1] }
        map { [ $_ => $self->current_revision( catdir $parent_dir, $_ ) ] }
        $self->current_subdirs($parent_dir);
}

sub filename_data {
    my ( $self, $directory, $revision ) = @_;
    return catfile $directory, sprintf 'revision_%05d.data', $revision;
}

sub filename {
    my ( $self, $directory, $revision ) = @_;
    return catfile $directory, sprintf 'revision_%05d', $revision;
}

sub directory {
    my ( $self, $idkey ) = @_;
    return catdir(
        $self->Root,
        ( $idkey->has_domain  ? ( $idkey->domain )  : () ),
        ( $idkey->has_name    ? ( $idkey->name )    : () ),
        ( $idkey->has_version ? ( $idkey->version ) : () ),
        ( $idkey->has_window  ? ( $idkey->window )  : () ),
        ( $idkey->has_key     ? ( $idkey->key )     : () )
    );
}

sub delete_latest_revision {
    my ( $self, $idkey ) = @_;
    my $directory = $self->directory($idkey);
    $self->lock_record($directory);
    unlink $self->filename( $directory,
        $self->writable_revision($directory) );
    unlink $self->filename_data( $directory,
        $self->writable_revision($directory) );
    unlink catfile $directory, $CURRENTFILE;

   # if there was a freeze then the writable revision is greater than zero and
   # we are obligated to keep the directory around. Otherwise, drop it.
    if ( $self->writable_revision($directory) == 0 ) {
        unlink catfile $directory, $WRITABLEFILE;
    }
    rmdir $directory;
    $self->unlock_record($directory);
    return;
}

sub store {
    my ( $self, $idkey, $data, $formatted ) = @_;
    use Data::Dumper;
    confess
        'second return value from delivery/summary/globsummary function does not appear to be an array ref'
        . Dumper $data
        if 'ARRAY' ne ref $data;
    my $directory = $self->directory($idkey);
    return $self->delete_latest_revision($idkey) if 0 < scalar @{$data};
    if ( !-d $directory ) {
        mkpath $directory ;
    }
    $self->lock_record($directory);

    # TODO: make this thread safe writes with temp name and renames
    {
        my $wfile = $self->writable_revision_path($directory);
        if ( !-f $wfile ) {
            my $wh = IO::File->new( $wfile, 'w' );
            $wh->print( $self->writable_revision($directory) );
        }
    }

    # TODO: make this thread safe writes with temp name and renames
    {
        my $vfile = $self->current_revision_path($directory);
        if ( !-f $vfile ) {
            my $vh = IO::File->new( $vfile, 'w' );
            $vh->print( $self->writable_revision($directory) );
        }
    }

    # TODO: make this thread safe writes with temp name and renames
    {
        my $datafilename = $self->filename_data( $directory,
            $self->writable_revision($directory) );
        my $dfh = IO::File->new( $datafilename, 'w' );
        store_fd $data, $dfh
            or confess "NO DATA $PROCESS_ID $CHILD_ERROR $OS_ERROR PRINT "
            . to_json $data;
    }

    if ( defined $formatted ) {

      warn "WRITING FORMATTED $formatted";
        # TODO: make this thread safe writes with temp name and renames
        my $filename = $self->filename( $directory,
            $self->writable_revision($directory) );
        my $fh = IO::File->new( $filename, 'w' );
        $fh->print($formatted)
            or confess "NO DATA $PROCESS_ID $CHILD_ERROR $OS_ERROR PRINT "
            . $formatted;
    }

    return $self->unlock_record($directory);
}

sub lock_record {
    my ( $self, $directory ) = @_;
    return;
}

sub unlock_record {
    my ( $self, $directory ) = @_;
    return;
}

# State transition = add new atom to inbox

sub freeze {
    my ( $self, $idkey ) = @_;

    confess 'unimplemented' if $idkey ne 'what it will never be';

    # this should copy the current report to a new one, and increment CURRENT
    # AND WRITABLE.
    my $directory = $self->directory($idkey);

    $self->lock_record($directory);

    my $old_revision = $self->current_revision($directory);
    my $new_revision = $old_revision + 1;

    my $vfile = $self->current_revision_path($directory);
    if ( !-f $vfile ) {
        my $vh = IO::File->new( $vfile, 'w' );
        $vh->print($new_revision);
    }
    my $wfile = $self->writable_revision_path($directory);
    if ( !-f $wfile ) {
        my $wh = IO::File->new( $vfile, 'w' );
        $wh->print($new_revision);
    }

    my $oldkey = Replay::IdKey->new(
        revision => $old_revision,
        rule     => $idkey->rule,
        version  => $idkey->version,
        ( $idkey->window ? ( window => $idkey->window ) : () ),
        ( $idkey->key    ? ( key    => $idkey->key )    : () ),
    );

    $self->store(
        $idkey,
        $self->retrieve( $oldkey, 1 )->{DATA},
        $self->retrieve($oldkey)->{FORMATTED}
    );

    return $self->unlock_record($directory);

}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 NAME

Replay::ReportEngine::Filesystem - report implementation for base filesystem use

=head1 VERSION

Version 0.03

=head1 SYNOPSIS

Replay::ReportEngine::Filesystem->new( 
        config      => 
        { ReportEngines => {
          FileSystem=>{
              Access=>'public',  
              Root  => $storedir, 
          },
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

=head1 SUBROUTINES/METHODS

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

=head2 store( idkey, data=[...], formatted)

data is an array reference

save to our filesystem, this data and optionally the formatted information.

if data is empty, purge the indicated storage slot.

if it isn't, write the data to the data file and formatted to the formatted file

=head2 lock_record(directory)

lock_record so other workers don't modify this file path

=head2 unlock_record(directory)

unlock_record so other workers can modify this file path

=head2 freeze($idkey)

enact the freeze logic for filesystem

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

This does not currently properly do locking or support freeze

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

=head1 REPORT ENGINE MODEL ASSUMPTIONS

IdKey: object that indicates all the axis of selection for the data requested
Data: an array reference defined returned by the reporting functions of the rule being processed
Formatted: treated with no interpolation - some sort of blob that means something to the user

STATE DOCUMENT GENERAL TO REPORT ENGINE

CURRENT - the current or latest revision, if any. gets overwritten on update
WRITABLE - the revision that we can write to, exists even if there is no current report

STATE DOCUMENT SPECIFIC TO THIS IMPLEMENTATION

REVISIONS - all of the revisions are inside here.
REVISIONS->##->DATA - the data structure for revision ##
REVISIONS->##->FORMATTED - the blob scalar for revision ##

=head1 REPORT ENGINE IMPLEMENTATION METHODS 

=head2 (state) = retrieve ( idkey )

Unconditionally return the entire state record 

=head2 (revision|undef) = current ( idkey )

if there is a valid current report for this key, return the number.

otherwise return undefined to indicate 404

=head2 delete_latest_revision ( idkey )

Remove the current revision from the report store.

This implies that the entire node of the report tree should be
destroyed if there are no frozen versions in it!

throw an exception if there's an error

it is not an error if there is no current/latest revision

=head2 store( idkey, data=[...], formatted)

store this data and formatted blob at this idkey for later retrieval

This always stores in the latest report revision!

throw an exception if there is an error

=head2 

=cut

1;
