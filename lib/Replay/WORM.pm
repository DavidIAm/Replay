package Replay::WORM;

use Moose;
our $VERSION = '0.01';

use POSIX qw/strftime/;
use File::Spec qw//;
use Scalar::Util qw/blessed/;
use Try::Tiny;
use Time::HiRes qw/gettimeofday/;

has eventSystem => (is => 'ro', required => 1,);
has directory   => (is => 'ro', required => 0, default => '/var/log/replay');
has filehandles => (is => 'ro', isa      => 'HashRef', default => sub { {} });
has uuid => (is => 'ro', isa => 'Data::UUID', builder => '_build_uuid');

#Not a reference {"__CLASS__":"Replay::Message::Clock-0.01","createdTime":1404788821.43006,"function":"clock","line":"161","message":{"__CLASS__":"Replay::Types::ClockType","date":7,"epoch":1404788821,"hour":23,"isdst":1,"minute":7,"month":6,"weekday":1,"year":2014,"yearday":187},"messageType":"Timing","program":"/data/sandboxes/ihnend/sand_24525/wwwveh/Replay/lib//Replay/EventSystem.pm","receivedTime":1404788821.43014,"uuid":"EE5CD344-064C-11E4-93B3-86246D109AE0"} at /data/sandboxes/ihnend/sand_24525/wwwveh/Replay/lib//Replay/WORM.pm line 24.

# dummy implimentation - Log them to a file
sub BUILD {
    my $self = shift;
    mkdir $self->directory unless -d $self->directory;
    $self->eventSystem->origin->subscribe(
        sub {
            my $message   = shift;
            my $timeblock = $self->log($message);
            warn "Not a reference $message" unless ref $message;
            if (blessed $message && $message->isa('Replay::Message')) {
                push @{ $message->timeblocks }, $self->timeblock;
                $message->receivedTime(+gettimeofday);
                $message->uuid($self->newUuid) unless $message->uuid;
            }
            else {
                try {
                    push @{ $message->{timeblocks} }, $self->timeblock;
                    $message->{receivedTime} = gettimeofday;
                    $message->{uuid} ||= $self->newUuid;
                }
                catch {
                    warn "unable to push timeblock on message?" . $message;
                };
            }
            $self->eventSystem->derived->emit($message);
        }
    );
}

sub newUuid {
    my $self = shift;
    return $self->uuid->to_string($self->uuid->create());
}

sub serialize {
        my ($self, $message) = @_;
        return $message unless ref $message;
        return JSON->new->encode($message) unless blessed $message;
        return $message->stringify
            if blessed $message && $message->can('stringify');
        return $message->freeze if blessed $message && $message->can('freeze');
        return $message->serialize
            if blessed $message && $message->can('serialize');
        warn "blessed but no serializer found? $message";
}

sub log {
        my $self    = shift;
        my $message = shift;
        $self->filehandle->print($self->serialize($message) . "\n");
}

sub path {
        my $self = shift;
        File::Spec->catfile($self->directory, $self->timeblock . '-' . $self->eventSystem->config->{stage});
}

sub filehandle {
        my $self = shift;
        return $self->filehandles->{ $self->timeblock }
            if exists $self->filehandles->{ $self->timeblock }
            && -f $self->filehandles->{ $self->timeblock };
        umask 0664;
        open $self->filehandles->{ $self->timeblock }, '>>', $self->path
            or confess "Unable to open " . $self->path . " for append";
        return $self->filehandles->{ $self->timeblock };
}

sub timeblock {
        my $self = shift;
        return strftime '%Y-%m-%d-%H', localtime time;
}

sub _build_uuid {
        my $self;
        return $self->{uuid} ||= Data::UUID->new;
}

=head1 NAME

Replay::WORM - the write once read many module

=head1 VERSION

Version 0.01

=head1 SYNOPSIS

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

=head2 newUuid

return a brand new uuid

=cut

=head1 AUTHOR

David Ihnen, C<< <davidihnen at gmail.com> >>

=head1 BUGS

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
