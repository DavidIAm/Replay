package Replay::EventSystem::RabbitMQ::Connection;

use MooseX::Singleton;

our $VERSION = '0.02';

use Replay::Message;

use Carp qw/carp croak/;
use Net::RabbitMQ;
use Try::Tiny;
use Data::UUID;
use JSON;
use Scalar::Util qw/blessed/;
use Carp qw/confess/;

has config => (is => 'ro', isa => 'HashRef[Defined]', required => 1);

has rabbit => (
    is       => 'ro',
    isa      => 'Net::RabbitMQ',
    required => 1,
    builder  => '_build_rabbit',
    handles  => [
        qw( exchange_declare queue_declare queue_bind publish get ack reject channel_close )
    ],
    lazy => 1,
);

has last_allocated_channel => (is => 'rw', isa => 'Num', default => 0,);
has topic_name =>
    (is => 'ro', isa => 'Str', builder => '_build_topic_name', lazy => 1,);
has queue_name =>
    (is => 'ro', isa => 'Str', builder => '_build_queue_name', lazy => 1);

sub channel_open {
    my ($self) = @_;
    my $channel = $self->last_allocated_channel + 1;
    $self->last_allocated_channel($channel);
    $self->rabbit->channel_open($channel);
    return $channel;
}

use Data::Dumper;

sub _build_rabbit {
    my ($self) = @_;
    my $rabbit = Net::RabbitMQ->new;
    return $rabbit unless defined $self->config;
    $rabbit->connect($self->config->{host}, $self->config->{options});
    return $rabbit;
}

sub DEMOLISH {
    my ($self) = @_;
    my $number = $self->last_allocated_channel;
    if (ref $self->rabbit) {
        $self->rabbit->channel_close($number--) while $number||0 > 0;
    }
}

1;

__END__

=pod

=head1 NAME

Replay::EventSystem::RabbitMQ::Connection - Shared connection for rabbitmq

=head1 VERSION

Version 0.01

head1 SYNOPSIS

This is an Event System implimentation module targeting the RabbitMQ service
If you were to instantiate it independently, it might 
look like this.

my $cv = AnyEvent->condvar;

Replay::EventSystem::AWSQueue::Connection->new(
            host    => 'localhost',
            port    => '5672',
            user    => 'replay',
            password => 'replaypass',
            vhost   => 'replay',
            timeout => 5,
            tls     => 1,
            heartbeat => 5, 
            channel_max => 100, 
            frame_max => 1000,
);

=head1 SUBROUTINES/METHODS

=head2 channel_open

opens a new channel on the rabbitmq connection and returns the identifier of it
for later reference

=head2 DEMOLISH

Makes sure to properly clean up by closing all the channels

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
