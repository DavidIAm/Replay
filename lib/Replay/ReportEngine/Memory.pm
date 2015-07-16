package Replay::ReportEngine::Memory;

use Moose;
use Scalar::Util qw/blessed/;
use Replay::IdKey;
use Carp qw/croak carp cluck/;
use JSON qw/to_json/;
use File::Spec::Functions;
use File::Path qw/mkpath/;
use File::Slurp qw/read_file/;
use Readonly;
use Storable qw/store_fd thaw/;
use IO::Dir;

with 'Replay::Role::ReportEngine';

our $VERSION = q(0.03);

Readonly my $CURRENTFILE  => 'CURRENT';
Readonly my $WRITABLEFILE => 'WRITABLE';

has '+mode' => ( default => 'Memory' );

my $store = {};

sub retrieve {
    my ($self, $idkey, $structured) = @_;
    my $directory = $self->directory($idkey);
    my $revision  = $self->revision($idkey);
    return { EMPTY => 1 } unless defined $revision;    # CASE: NO CURRENT REPORT
    if ($structured) {
        return { EMPTY => 0, DATA => $directory->{REVISIONS}{$revision}{DATA} } if exists $directory->{REVISIONS}{$revision}{DATA};
        return { EMPTY => 1 };
    }
    return { EMPTY => 0, FORMATTED => $directory->{REVISIONS}{$revision}{FORMATTED} } if exists $directory->{REVISIONS}{$revision}{FORMATTED};
    return { EMPTY => 1 };
}

sub writable_revision_path {
    my ($self, $directory) = @_;
    return $directory->{REVISIONS}{$directory->{WRITABLE}}||={};
}

sub current_revision_path {
    my ($self, $directory) = @_;
    return $directory->{REVISIONS}{$directory->{CURRENT}} ||={};
}

sub writable_revision {
    my ($self, $directory) = @_;
    return 0 unless exists $directory->{WRITABLE};
    return $directory->{WRITABLE} || 0;
}

sub current_revision {
    my ($self, $directory) = @_;
    return undef unless exists $directory->{CURRENT};
    return $directory->{CURRENT} || 0;
}

sub current {
    my ($self, $idkey) = @_;
    return $self->current_revision($self->directory($idkey));
}

# retrieves all the keys that point to valid deliveries in the current window
sub subdirs {
    my ($self, $parentDir) = @_;
    my @subdirs;
    confess "not a ref" unless 'HASH' eq ref $parentDir;
    foreach my $entry (keys %{$parentDir}) {
        next if $entry eq 'CURRENT';
        next if $entry eq 'REVISIONS';
        next if $entry eq 'WRITABLE';
        push @subdirs, $entry;
    }
    return @subdirs;
}

# filters a list of directories by those which contain a CURRENT file
sub current_subdirs {
    my ($self, $parentDir) = @_;
    return
        grep { exists $parentDir->{$_}{CURRENT} }
        $self->subdirs($parentDir);
}

# retrieves all the keys that point to valid summaries in the current
# rule-version
sub delivery_keys {
    my ($self, $sumkey) = @_;
    my $parentDir = $self->directory($sumkey);
    confess "not a ref" unless 'HASH' eq ref $parentDir;
    map {
        Replay::IdKey->new(
            name     => $sumkey->name,
            version  => $sumkey->version,
            window   => $sumkey->window,
            key      => $_->[0],
            revision => $_->[1],
            )
        } grep { defined $_->[1] }
        map { [ $_ => $self->current_revision($parentDir->{$_}||={}) ] }
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
        map { [ $_ => $self->current_revision($parentDir->{$_}) ] }
        $self->current_subdirs($parentDir);
}

sub directory {
    my ($self, $idkey) = @_;
    my $s = $store->{$idkey->name}{$idkey->version} ||= {};
    $s = $s->{$idkey->{window}} ||= {} if $idkey->has_window;
    $s = $s->{$idkey->{key}} ||= {} if $idkey->has_key;
    return $s;
}

sub delete_latest_revision {
    my ($self, $idkey) = @_;
    my $directory = $self->directory($idkey);
    $self->lock($directory);
    delete $directory->{REVISIONS}{$self->writable_revision($directory)};
    delete $directory->{CURRENT};

    # if there was a freeze then the writable revision is greater than zero and
    # we are obligated to keep the directory around. Otherwise, drop it.
    delete $directory->{WRITABLE}
        if $self->writable_revision($directory) == 0;
    $self->unlock($directory);
    return;
}

sub store {
    my ($self, $idkey, $data, $formatted) = @_;
    confess
        "first return value from delivery/summary/globsummary function does not appear to be an array ref"
        unless 'ARRAY' eq ref $data;
    my $directory = $self->directory($idkey);
    return $self->delete_latest_revision($idkey) unless scalar @{$data};
    $self->lock($directory);

    $directory->{WRITABLE} = $self->writable_revision($directory);
    $directory->{CURRENT}  = $self->writable_revision($directory);

    $directory->{REVISIONS}{ $self->writable_revision($directory) }{DATA} = $data;

    if (defined $formatted) {
        $directory->{REVISIONS}{ $self->writable_revision($directory) }{FORMATTED}
            = $formatted;

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
    my ($self, $part, $idkey) = @_;

    # this should copy the current report to a new one, and increment CURRENT
    # AND WRITABLE.
    my $directory = $self->directory($idkey);

    $self->lock($directory);

    my $old_revision = $self->current_revision($directory);
    my $new_revision = $old_revision + 1;

    $directory->{CURRENT} = $directory->{WRITABLE} = $new_revision;

    my $deepcopy = thaw(Storable::freeze($self->current_revision_path($directory)));

    $self->store(
        $part, $idkey,
        $deepcopy->{DATA},
        $deepcopy->{FORMATTED},
    );

    $self->notify_freeze($idkey);
    $self->unlock($directory);
}

1;

__END__

=pod

=head1 NAME

Replay::ReportEngine::Memory - report implimentation for memory - testing only

=head1 VERSION

Version 0.03

=head1 SYNOPSIS

Replay::ReportEngine::Memory->new( 
        config      => 
        { ReportEngine => { Mode => Memory, },
        ruleSource  => $self->ruleSource,
        eventSystem => $self->eventSystem,
    );

Initializes the Memory report engine.

=head1 DESCRIPTION

Data structure follows the format of the idkey.

The hierarchy names are joined together to form a data structure.

$store->{rulename}{versionnum}{windowname}{keyname}

if a key or window isn't relevant (for summaries and globsummary) the hash may or may not be present.

keys within a directory, and what they mean:

WRITABLE - contains a number, the revision number of the current version for writing.

if there is no WRITABLE, this layer of report has never had data in it.

CURRENT - contains a number, the revision number of the latest existing report

if there is no CURRENT, the report is 404, not available.

REVISIONS->#####->FORMATTED - contains the 'formatted' report - in whatever format programmer desires.

REVISIONS->#####->DATA - contains the 'data' part of report - in native structure

a 'purge' happens when a report or summary returns empty list, indicating 'no state to report'. The system will remove the current revision file, and the CURRENT file to indicate there is no report available at this location any longer.

a 'freeze' request acts on the latest revision.  the writable revision is moved up one and the previously latest version is copied to it. The frozen version will never be removed.

=head1 METHODS

=head2 retrieve(idkey, structured)

structured is boolean

return the raw data if structured is set

otherwise return the formatted form of the report

=head2 writable_revision_path(parentnode)

return the data node writable revision data in this node

=head2 current_revision_path(parentnode)

return the path for the current revision data in this node

=head2 writable_revision(parentnode)

return the writable revision appropriate for this node

=head2 current_revision(parentnode)

return the current revision appropriate for this node

=head2 current(idkey)

return the current revision appropriate for this key

=head2 subdirs(parentnode)

return the list of keys to hierarchy keys that exist immediately below this node

=head2 current_subdirs(parentnode)

return the list of keys to hierarchy keys that exist immediately below this node

=head2 delivery_keys(idkey)

return the list of keys that have CURRENT revision values for this window location

=head2 summary_keys(idkey)

return the list of windows that have CURRENT revision values for this rule-version location

=head2 directory(idkey)

return the node appropriate for this key

=head2 delete_latest_revision(idkey)

Remove the current report for this key

=head2 store(part=(delivery|summary|globsummary), idkey, data=[...], formatted)

part is one of 'delivery', 'summary', 'globsummary'

data is an array reference

save to our memory tree, this data and optionally the formatted information.

if data is empty, purge the indicated storage slot.

if it isn't, write the data to the data file and formatted to the formatted file

=head2 lock(directory)

lock so other workers don't modify this node

=head2 unlock(directory)

unlock so other workers can modify this node

=head2 freeze($idkey)

enact the freeze logic for memory

=head1 AUTHOR

David Ihnen, C<< <davidihnen at gmail.com> >>

=head1 BUGS

Locking is not implimented, but for testing in memory it shouldn't be important

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

STATE DOCUMENT SPECIFIC TO THIS IMPLIMENTATION

REVISIONS - all of the revisions are inside here.
REVISIONS->##->DATA - the data structure for revision ##
REVISIONS->##->FORMATTED - the blob scalar for revision ##

=head1 REPORT ENGINE IMPLIMENTATION METHODS 

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
