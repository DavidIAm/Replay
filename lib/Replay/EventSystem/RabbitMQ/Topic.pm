package Replay::EventSystem::RabbitMQ::Topic;

use Moose;

our $VERSION = '0.02';

use Replay::Message;

#use Replay::Message::Clock;
use Carp qw/carp croak/;

use Perl::Version;
use Net::RabbitMQ;
use Try::Tiny;
use Data::UUID;
use JSON;
use Scalar::Util qw/blessed/;
use Carp qw/cluck confess/;

has rabbit => (
    is       => 'ro',
    isa      => 'Replay::EventSystem::RabbitMQ',
    required => 1,
    handles  => [qw( publish )],
);

has channel => (
    is        => 'ro',
    isa       => 'Num',
    builder   => '_new_channel',
    lazy      => 1,
    predicate => 'has_channel',
);

has purpose => (is => 'ro', isa => 'Str', required => 1,);

has topic => (is => 'ro', isa => 'Replay::EventSystem::RabbitMQ::Topic',);

has exchange_type => (is => 'ro', isa => 'Str', default => 'topic',);

has passive => (is => 'ro', isa => 'Bool', default => 0,);

has durable => (is => 'ro', isa => 'Bool', default => 1,);

has auto_delete => (is => 'ro', isa => 'Bool', default => 0,);

has routing_key =>
    (is => 'ro', isa => 'Str', builder => '_build_routing_key', lazy => 1);

has topic_name =>
    (is => 'ro', isa => 'Str', builder => '_build_topic_name', lazy => 1);

has topic => (
    is      => 'ro',
    isa     => 'Replay::EventSystem::RabbitMQ::Topic',
    builder => '_build_topic',
    lazy    => 1
);

sub _new_channel {
    my ($self) = @_;
    return $self->rabbit->channel_open;
}

sub emit {
    my ($self, $message) = @_;

    # THIS MUST DOES A Replay::Role::Envelope
    confess "Can only emit Replay::Role::Envelope consumer"
        unless $message->does('Replay::Role::Envelope');

#    warn __FILE__ .": EMITTING ON " . $self->topic_name . " : " . $message->{MessageType};

    $self->topic->publish(
        $self->channel, $self->topic_name,
        to_json($message->marshall),
        { exchange => $self->topic_name }
    );

    return $message->UUID;
}

sub DEMOLISH {
    my ($self) = @_;
    if ($self->has_channel && defined $self->rabbit) {
        $self->rabbit->channel_close($self->channel);
    }
    return;
}

sub _build_routing_key {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my ($self) = @_;
    confess q(No purpose) if not $self->purpose;
    return join q(.), 'replay', $self->rabbit->config->{stage}, $self->purpose;
}

sub _build_topic_name {     ## no critic (ProhibitUnusedPrivateSubroutines)
    my ($self) = @_;
    confess q(No purpose) unless defined $self->purpose;
    return join q(_), $self->rabbit->config->{stage}, 'replay', $self->purpose;
}

sub _build_topic {          ## no critic (ProhibitUnusedPrivateSubroutines)
    my ($self) = @_;
    $self->rabbit->exchange_declare(
        $self->channel,
        $self->topic_name,
        {   exchange_type => $self->exchange_type,
            passive       => $self->passive,
            durable       => $self->durable,
            auto_delete   => $self->auto_delete
        }
    );
    return $self;
}

1;

__END__

=pod

=head1 NAME

Replay::EventSystem::RabbitMQ::Topic - RabbitMQ Exchange implimentation

=head1 VERSION

Version 0.01

head1 SYNOPSIS

This is an Event System implimentation module targeting the RabbitMQ service
If you were to instantiate it independently, it might 
look like this.

my $cv = AnyEvent->condvar;

Replay::EventSystem::RabbitMQ::Topic->new(
    purpose => $purpose,
    config  => {
        stage    => 'test',
        RabbitMQ => {
            host    => 'localhost',
            port    => '5672',
            user    => 'replay',
            pass    => 'replaypass',
            vhost   => 'replay',
            timeout => 5,
            tls     => 1,
            tune    => { heartbeat => 5, channel_max => 100, frame_max => 1000 },
        },
    }
);

$cv->recv;


Utilizers should expect the object instance to be a singleton per each $purpose.

The account provided is expected to have the permissions to create exchanges and queues on the indicated virtualhost.

It will create SNS topic for the indicated purpose named <stage>-replay-<purpose>

It will create distinct SQS queues for the instance, named <stage>-replay-<purpose>-<uuid>

It will also subscribe the queue to the topic.

=head1 SUBROUTINES/METHODS

=head2 subscribe( sub { my $message = shift; ... } )

each code reference supplied is called with each message received, each time
the message is received.  This is how applications insert their hooks into 
the channel to get notified of the arrival of messages.

=head2 emit( $message )

Send the specified message on the topic for this channel

=head2 poll()

Gets new messages and calls the subscribed hooks with them

=head2 DEMOLISH

Makes sure to properly clean up and disconnect from queues

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
