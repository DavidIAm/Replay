package Replay;

use 5.006;
use strict;
use warnings FATAL => 'all';

=head1 NAME

Replay - The great new Replay!

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use Replay;

my $eventSystem = Replay::EventSystem->new(timeout => 2);

my $ruleSource = Replay::RuleSource->new(
    rules       => [ new TESTRULE ],
    eventSystem => $eventSystem
);

my $storage = Replay::StorageEngine->new(
    ruleSource  => $ruleSource,
    eventSystem => $eventSystem
);

my $replay = Replay->new(
    ruleSource    => $ruleSource,
    eventSystem   => $eventSystem,
    storageEngine => $storageEngine,
);

my $reducer = Replay::Reducer->new(replay => $replay);

my $mapper = Replay::Mapper->new(replay => $replay);

...

=head1 EXPORT

A list of functions that can be exported.  You can delete this section
if you don't export anything, such as for a purely object-oriented module.

=head1 SUBROUTINES/METHODS

=head2 function1

=cut

sub function1 {
}

=head2 function2

=cut

sub function2 {
}

=head1 AUTHOR

David Ihnen, C<< <davidihnen at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-replay at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Replay>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




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

1; # End of Replay



#!/usr/bin/perl

package TESTRULE;

use Moose;
extends 'Replay::BusinessRule';
use List::Util qw//;

has '+name' => (default => __PACKAGE__,);

override match => sub {
    my ($self, $message) = @_;
    return $message->{is_interesting};
};

override window => sub {
    my ($self, $message) = @_;
    return $message->{window} if $message->{window};
    return super;
};

override keyValueSet => sub {
    my ($self, $message) = @_;
    my @keyvalues = ();
    foreach my $key (keys %{$message}) {
        next unless 'ARRAY' eq ref $message->{$key};
        foreach (@{ $message->{$key} }) {
            push @keyvalues, $key, $_;
        }
    }
    return @keyvalues;
};

override compare => sub {
    my ($self, $aa, $bb) = @_;
    return ($aa || 0) <=> ($bb || 0);
};

override reduce => sub {
    my ($self, @state) = @_;
    return List::Util::reduce { $a + $b } @state;
};

package main;

use Test::Most;

# test the event transition interface0

# an event transition has a match/map

my $interesting = { interesting => 1 };

my $tr = new TESTRULE->new;
die unless $tr->version;
is $tr->version, 1, 'version returns';

my $intmessage    = { is_interesting => 1 };
my $boringmessage = { is_interesting => 0 };

ok $tr->match($intmessage), 'is interesting';
ok !$tr->match($boringmessage), 'is not interesting';

my $nowindowmessage = { vindow => 'sometime' };
my $windowmessage   = { window => 'sometime' };
ok $tr->window($nowindowmessage), 'alltime';
ok $tr->window($windowmessage),   'sometime';

my $funMessage = { a => [ 5, 1, 2, 3, 4 ], is_interesting => 1 };
my $notAfterAll = { b => [ 1, 2, 3, 4 ] };

is_deeply [ $tr->keyValueSet($funMessage) ],
    [ a => 5, a => 1, a => 2, a => 3, a => 4 ], 'expands';

is_deeply [ $tr->keyValueSet({ b => [ 1, 2, 3, 4 ] }) ],
    [ b => 1, b => 2, b => 3, b => 4 ];

my $eventSystem = TestEventSystem->new(timeout => 2);
my $ruleSource = Replay::RuleSource->new(
    rules       => [ new TESTRULE ],
    eventSystem => $eventSystem
);
my $storage = Replay::StorageEngine->new(
    ruleSource  => $ruleSource,
    eventSystem => $eventSystem
);
my $reducer = Replay::Reducer->new(
    eventSystem   => $eventSystem,
    ruleSource    => $ruleSource,
    storageEngine => $storage
);
my $mapper = Replay::Mapper->new(
    ruleSource  => $ruleSource,
    eventSystem => $eventSystem,
    storageEngine => $storage,
);

$eventSystem->emit($funMessage);

is_deeply [
    $storage->fetchCanonicalState(
        { name => 'TESTRULE', version => 1, window => 'alltime', key => 'a' }
    )
    ],
    [], 'nonexistant';

$eventSystem->run;

use Data::Dumper;
is_deeply [
    $storage->fetchCanonicalState(
        { name => 'TESTRULE', version => 1, window => 'alltime', key => 'a' }
    )
    ],
    [15];

done_testing();
