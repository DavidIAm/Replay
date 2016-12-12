package Replay::WORM;

use Moose;
our $VERSION = '0.02';

use POSIX qw/strftime/;
use File::Spec qw//;
use Scalar::Util qw/blessed/;
use Try::Tiny;
use Time::HiRes qw/gettimeofday/;
use Carp qw/carp croak/;
use Readonly;

Readonly my $UMASK => 6;

has eventSystem => ( is => 'ro', required => 1, );
has directory =>
    ( is => 'ro', required => 0, lazy => 1, builder => '_build_log_dir' );
has filehandles => ( is => 'ro', isa => 'HashRef', default => sub { {} } );
has UUID => ( is => 'ro', isa => 'Data::UUID', builder => '_build_uuid' );
has config => ( is => 'ro', required => 1, );

# dummy implimentation - Log them to a file
sub BUILD {
    my $self = shift;
    if ( not -d $self->directory ) {
        mkdir $self->directory;
    }
    $self->eventSystem->origin->subscribe(
        sub {
            my $message   = shift;
            my $timeblock = $self->log($message);
            carp "Not a reference $message" if not ref $message;
            if ( blessed $message && $message->isa('Replay::Message') ) {
                $message = $message->marshall;
            }
            try {
                push @{ $message->{Timeblocks} }, $self->timeblock;
                $message->{ReceivedTime} = gettimeofday;
                $message->{UUID} ||= $self->new_uuid;
            }
            catch {
                carp q(unable to push timeblock on message?) . $message;
            };
            $self->eventSystem->map->emit($message);
        }
    );
    return;
}

sub new_uuid {
    my $self = shift;
    return $self->UUID->to_string( $self->UUID->create() );
}

sub serialize {
    my ( $self, $message ) = @_;
    return $message if not ref $message;
    return JSON->new->encode($message) if not blessed $message;
    return $message->stringify
        if blessed $message && $message->can('stringify');
    return $message->freeze if blessed $message && $message->can('freeze');
    return $message->serialize
        if blessed $message && $message->can('serialize');
    carp "blessed but no serializer found? $message";
    return;
}

sub log {    ## no critic (ProhibitBuiltinHomonyms)
    my $self    = shift;
    my $message = shift;
    return $self->filehandle->print( $self->serialize($message) . qq(\n) );
}

sub path {
    my $self = shift;
    return File::Spec->catfile( $self->directory,
        $self->timeblock . q(-) . $self->config->{stage} || 'nostage' );
}

sub filehandle {
    my $self = shift;
    return $self->filehandles->{ $self->timeblock }
        if exists $self->filehandles->{ $self->timeblock }
        && -f $self->filehandles->{ $self->timeblock };
    my $current_umask = umask;
    umask $UMASK;    # not entirely sure why this works
    open $self->filehandles->{ $self->timeblock }, '>>', $self->path
        or confess q(Unable to open ) . $self->path . q( for append);
    umask $current_umask;
    return $self->filehandles->{ $self->timeblock };
}

sub timeblock {
    my $self = shift;
    return strftime '%Y-%m-%d-%H', localtime time;
}

sub _build_uuid {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my $self;
    return $self->{UUID} ||= Data::UUID->new;
}

sub _build_log_dir {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my ($self) = @_;
    return $self->config->{WORM}->{'Directory'} || '/var/log/replay';
}

1;

__END__

=pod

=head1 NAME

Replay::WORM - the write once read many module

=head1 VERSION

Version 0.01

=head1 SYNOPSIS

  Replay::WORM->new(
    eventSystem => $eventsystem,
    config => {
      stage => "STAGENAME",
      WORM => { Directory => 'writable_directory_to_log_to' }
    }
  );

=head1 CONFIGURATION AND ENVIRONMENT

Implied by context

=head1 DESCRIPTION

This is the WORM component of the replay system.  Its purpose is to log 
the origin data stream for later replay.

=head1 SUBROUTINES/METHODS

=head2 BUILD

subscribes to origin channel

=head2 serialize

how it makes a message for the log file

=head2 log

write to the log file handle for this time block

=head2 path

Accessor for the current pathname of the log file

=head2 filehandle

Accessor for the current filehandle to the current log file

=head2 timeblock

resolves the current time into a particular timeblock

=head2 _build_uuid

creates the uuid object for creating uuids with on demand

=head2 _build_log_dir

grabs the configuration of the log directory

=head2 new_uuid

return a brand new uuid

=cut

=head1 AUTHOR

David Ihnen, C<< <davidihnen at gmail.com> >>

=head1 DIAGNOSTICS

nothing to say here

=head1 DEPENDENCIES

Nothing outside the normal Replay world

=head1 INCOMPATIBILITIES

Nothing to report

=head1 BUGS AND LIMITATIONS

Please report any bugs or feature requests to C<bug-replay at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Replay>.  I will be notified, and then you'll automatically be notified of progress on your bug as I make changes .

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
