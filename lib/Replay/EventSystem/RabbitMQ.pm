package Replay::EventSystem::RabbitMQ;

use Moose;

our $VERSION = '0.02';

use Replay::EventSystem::Base;
with 'Replay::EventSystem::Base';

use Replay::EventSystem::RabbitMQ::Connection;
use Replay::EventSystem::RabbitMQ::Queue;
use Replay::EventSystem::RabbitMQ::Topic;
use Replay::Message;

#use Replay::Message::Clock;
use Carp qw/carp croak confess/;

use Perl::Version;
use Net::RabbitMQ;
use Try::Tiny;
use Data::UUID;
use JSON;
use Scalar::Util qw/blessed/;
use Carp qw/confess/;

has purpose => (is => 'ro', isa => 'Str', required => 1,);
has subscribers => (is => 'ro', isa => 'ArrayRef', default => sub { [] },);

has config => (is => 'ro', isa => 'HashRef[Item]', required => 1);

has rabbit => (
    is      => 'ro',
    isa     => 'Replay::EventSystem::RabbitMQ::Connection',
    builder => '_build_rabbit',
    handles => [
        qw(
            channel_close
            channel_open
            exchange_declare
            queue_declare
            queue_bind
            publish
            get
            ack
            reject
            )
    ],
    lazy    => 1,
    clearer => 'done_with_object',
);

has queue => (
    is        => 'ro',
    isa       => 'Replay::EventSystem::RabbitMQ::Queue',
    builder   => '_build_queue',
    predicate => 'has_queue',
    handles   => [qw( _receive )],
    lazy      => 1,
);

has topic => (
    is      => 'ro',
    isa     => 'Replay::EventSystem::RabbitMQ::Topic',
    builder => '_build_topic',

    # Why won't this match the require of base?
    #  handles => [ qw( emit ) ],
    lazy => 1,
);

sub _build_rabbit {
    my ($self) = @_;
    try {
        return Replay::EventSystem::RabbitMQ::Connection->instance;
    }
    catch {
        Replay::EventSystem::RabbitMQ::Connection->initialize(
            config => $self->config->{EventSystem}{RabbitMQ});
        return Replay::EventSystem::RabbitMQ::Connection->instance;
    };
}

sub emit {
    my ($self, $message) = @_;

    $message = Replay::Message->new($message) unless blessed $message;
    # THIS MUST DOES A Replay::Envelope
    confess "Can only emit Replay::Envelope consumer"
        unless $message->does('Replay::Envelope');
    my $uuid = $message->UUID;

    $self->topic->emit($message) or return;
    return $self->topic->emit($message);
}

sub poll {
    my ($self) = @_;
    my $handled = 0;

    # only check the channels if we have been shown an interest in
    foreach my $message ($self->_receive()) {
        next if not scalar(@{ $self->subscribers });
        $handled++;
        try {
            foreach my $subscriber (@{ $self->subscribers }) {
                $subscriber->($message->body);
            }
            $message->ack;
        }
        catch {
            $message->nack;
            carp q(There was an exception while processing message through subscriber )
                . $_;
        };
    }
    return $handled;
}

sub subscribe {
    my ($self, $callback) = @_;
    croak 'callback must be code' if 'CODE' ne ref $callback;
    push @{ $self->subscribers }, $callback;
    return;
}

sub _build_topic {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my ($self) = @_;
    return Replay::EventSystem::RabbitMQ::Topic->new(
        rabbit        => $self,
        purpose       => $self->purpose,
        exchange_type => $self->mode,
    );

}

sub _build_queue {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my ($self) = @_;
    return Replay::EventSystem::RabbitMQ::Queue->new(
        rabbit        => $self,
        purpose       => $self->purpose,
        topic         => $self->topic,
        exchange_type => $self->mode,
    );

}

sub done {
    my ($self) = @_;

    #  $self->rabbit->_clear_instance;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 NAME

Replay::EventSystem::RabbitMQ - RabbitMQ Exchange/Queue implimentation

=head1 VERSION

Version 0.01

head1 SYNOPSIS

This is an Event System implimentation module targeting the RabbitMQ service
If you were to instantiate it independently, it might 
look like this.

my $cv = AnyEvent->condvar;

Replay::EventSystem::AWSQueue->new(
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
