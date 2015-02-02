package Replay::ReportEngine::Mongo;

use Moose;
use Scalar::Util qw/blessed/;
use Replay::IdKey;
use Carp qw/croak carp cluck/;
use JSON qw/to_json/;
use MongoDB;
use MongoDB::OID;

extends 'Replay::BaseReportEngine';
with (qw(Replay::Role::MongoDB)
);
our $VERSION = q(0.01);

#my $store = {};


sub _build_mongo {    
    my ($self) = @_;
    my $db = MongoDB::MongoClient->new();
    $db->authenticate($self->dbauthdb, $self->dbuser, $self->dbpass);
    return $db;
}

sub _build_dbpass {   
    my $self = shift;
    return $self->config->{ReportEngine}->{MongoPass}||$self->config->{MongoPass};
}

sub _build_dbuser {  
    my $self = shift;
    return $self->config->{ReportEngine}->{MongoUser}$self->config->{MongoUser};
}

sub _build_dbauthdb {   
    my $self = shift;
    return $self->config->{ReportEngine}->{MongoAuthDB}||$self->config->{MongoAuthDB} || 'admin';
}

sub _build_dbname {   
    my $self = shift;
    return $self->config->{ReportEngine}->{Name}||$self->config->{stage}."-report-" . '-replay';
}

sub _build_db {        
    my ($self) = @_;
    my $config = $self->config;
    my $db     = $self->mongo->get_database($self->dbname);
    return $db;
}

#report on a key
sub delivery { #get the named documet lates version
    my ($self, $idkey) = @_;
    
    return $self->document($idkey);
}

# reports on a windows and a key
sub summary { #
    my ($self, $idkey) = @_;
    
    return $self->collection($idkey)->find({ idkey => $idkey->window."-winder" });

}

# reports all windows for a rule version

sub globsummary {
    my ($self, $idkey) = @_;
     return $self->collection($idkey)->find({ idkey => "all" });
    return;
}

sub revision_file { #shows the curent revsion internal to file
    my ($self, $directory) = @_;
    return catfile($directory, 'CURRENT');
}

sub latest {
   my ($self, $directory) = @_;
   return $self->collection($idkey)->find({ idkey => "all" });

}

# get the revsion that is returning
sub revision {
    my ($self, $idkey, $directory) = @_;
    if ($idkey->revision eq 'latest') {
        return $self->latest($directory);
    }
    else {
        return $idkey->revision;
    }
}

sub filename {
    my ($self, $directory, $revision) = @_;
    return catfile $directory, sprintf 'version_%05d', $revision;
}

sub directory_delivery {
  my ($self, $idkey) = @_;
  return catdir($self->config->{reportFilesystemRoot},
        $idkey->name, $idkey->version, $idkey->window, $idkey->key);
}

sub delete_latest_report {
    my ($self, $directory) = @_;
    unlink $self->filename($directory, $self->latest($directory));
    unlink catfile $directory, 'CURRENT';
    rmdir $directory;
    return;
}




#Api
# storres itme at the Key levle
sub store_delivery {
    my ($self, $idkey,$state,$format) = @_;
    
    return  $self->store($idkey->key,$state,$formatted);

}

sub store {
     my ($self, $key, $reportdata, $formatted) = @_;
       use JSON;
       my $r = $self->collection($idkey)->update(
           { idkey => $key,
                 revision => $idkey->revision },
           {   q^$^ . 'set' => { formatted => $formatted, data => $reportdata },
               q^$^ . 'setOnInsert' => { idkey => $idkey->cubby, revision => $idkey->revision, IdKey => $idkey->pack }
           },
           { upsert => 1, multiple => 0 },
       );
       super();
       return $r;
};




sub directory_summary {
  my ($self, $idkey) = @_;
  return catdir($self->config->{reportFilesystemRoot},
        $idkey->name, $idkey->version, $idkey->window);
}

#stores item at the winder level
sub store_summary {
    my ($self, $idkey, @state) = @_;
    my $directory = $self->directory_summary($idkey);
    return $self->store($directory, $self->revision($idkey, $directory), @state);
}

sub directory_globsummary {
  my ($self, $idkey) = @_;
  return catdir($self->config->{reportFilesystemRoot},
        $idkey->name, $idkey->version);
}
#stores item at the rule version level

sub store_globsummary {
    my ($self, $idkey, @state) = @_;
    my $directory = $self->directory_globsummary($idkey);
    return $self->store($directory, $self->revision($idkey, $directory), @state);
}

# State transition = add new atom to inbox
# get a report and keep a copy 
# ie invoice 
sub freeze {
    confess "unimplimented";
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
