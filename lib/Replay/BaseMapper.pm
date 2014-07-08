package Replay::BaseMapper;

use Moose;

our $VERSION = '0.01';

has ruleSource => (is => 'ro', isa => 'Replay::RuleSource',);

has eventSystem => (is => 'ro', required => 1,);

has storageClass => (is => 'ro',);

has storageEngine => (
    is      => 'ro',
    isa     => 'Replay::StorageEngine',
    builder => 'buildStorageSink',
    lazy    => 1,
);

sub buildStorageSink {
    my $self = shift;
    die "no storage class?" unless $self->storageClass;
    $self->storageClass->new(ruleSource => $self->ruleSource);
}

sub BUILD {
    my $self = shift;
    die "need either storageEngine or storageClass"
        unless $self->storageEngine || $self->storageClass;
    $self->eventSystem->derived->subscribe(
        sub {
            $self->map(@_);
        }
    );
}

sub map {
    my $self    = shift;
    my $message = shift;
    die "I CANNOT MAP UNDEF" unless defined $message;
    while (my $rule = $self->ruleSource->next) {
        next unless $rule->match($message);
        my @all = $rule->keyValueSet($message);
        die "key value list from key value set must be even" if scalar @all % 2;
        my $window = $rule->window($message);
        while (scalar @all) {
            my $key  = shift @all;
            my $atom = shift @all;
            die "unable to store"
                unless $self->storageEngine->absorb(
                Replay::IdKey->new(
                    {   name    => $rule->name,
                        version => $rule->version,
                        window  => $window,
                        key     => $key
                    }
                ),
                $atom,
                {   timeblocks      => $message->{timeblocks},
                    domain       => $self->eventSystem->domain,
                    ruleversions => [
                        { rule => $rule->name, version => $rule->version },
                        @{ $message->{ruleversions} || [] }
                    ]
                }
                );
        }
    }
}

=head1 NAME

Replay::BaseMapper - The base class for the mapper functionality

=head1 VERSION

Version 0.01

=head1 SYNOPSIS

This is the basic functionality for considering each incoming message and 
mapping it to a set of key value pairs that will be absorbed into the storage
engine.

=head1 SUBROUTINES/METHODS

=head2 map ($message)

step through each rule available in the rule source.

ignore the rule if negative response to the ->match(message) subrule 

map the message to a set of key => value pairs by calling the ->keyValueSet(message) subrule

get the window by calling the ->window(message) subrule

get the rule by calling the ->rule(message) subrule

get the version by calling the ->version(message) subrule

sets the domain operating in from the event system

adds to the set of timeblocks as relevant

adds to the set of ruleversions as relevant

=head2 BUILD

subscribes to the derived channel

=head2 buildStorageSink

builder for getting the storage engine using the rule source

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

1;    # End of Replay

1;
