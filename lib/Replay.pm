package Replay;

use 5.006;
use strict;
use warnings FATAL => 'all';
our $VERSION = '0.03';

use Moose;
use AnyEvent;
use Replay::StorageEngine 0.03;
use Replay::ReportEngine 0.03;
use Replay::EventSystem 0.02;
use Replay::RuleSource 0.02;
use Replay::Reporter 0.03;
use Replay::Janitor 0.01;
use Replay::Reducer 0.02;
use Replay::Mapper 0.02;
use Replay::Types::Types 0.02;
use Replay::WORM 0.02;
use Carp qw/croak/;

has rules => ( is => 'ro', isa => 'ArrayRef[BusinessRule]', required => 1 );

has ruleSource => (
    is      => 'ro',
    isa     => 'Replay::RuleSource',
    builder => '_build_rule_source',
    lazy    => 1,

);

sub _build_rule_source {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my $self         = shift;
    my $rules        = $self->rules;
    my $event_system = $self->eventSystem;

    my $rule_source = Replay::RuleSource->new(
        rules       => $rules,
        eventSystem => $event_system
    );
    return $rule_source;
}

has eventSystem => (
    is      => 'ro',
    isa     => 'Replay::EventSystem',
    builder => '_build_event_system',
    lazy    => 1,
);

sub _build_event_system {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my $self   = shift;
    my $config = $self->config;
    my $event  = Replay::EventSystem->new(
        config => $config,
        domain => $config->{EventSystem}->{domain}
    );
    return $event;
}

has reportEngine => (
    is      => 'ro',
    isa     => 'Replay::ReportEngine',
    builder => '_build_report_engine',
    lazy    => 1,

);

sub _build_report_engine {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my $self           = shift;
    my $config         = $self->config;
    my $event_system   = $self->eventSystem;
    my $rule_source    = $self->ruleSource;
    my $storage_engine = $self->storageEngine;
    my $report         = Replay::ReportEngine->new(
        config        => $config,
        eventSystem   => $event_system,
        ruleSource    => $rule_source,
        storageEngine => $storage_engine,
    );
    return $report;
}

has storageEngine => (
    is      => 'ro',
    isa     => 'Replay::StorageEngine',
    builder => '_build_storage_engine',
    lazy    => 1,

);

has config => ( is => 'ro', isa => 'HashRef[Item]', required => 1, );

sub _build_janitor {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my $self         = shift;
    my $event_system = $self->eventSystem;
    my $storage_engine = $self->storageEngine;
    my $janitor = Replay::Janitor->new(
      eventSystem => $event_system,
      storageEngine => $storage_engine,
      config      => $self->config
    );
    return $janitor;
}

sub _build_storage_engine {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my $self         = shift;
    my $config       = $self->config;
    my $event_system = $self->eventSystem;
    my $rule_source  = $self->ruleSource;

    my $store = Replay::StorageEngine->new(
        config      => $config,
        ruleSource  => $rule_source,
        eventSystem => $event_system
    );
    return $store;
}

has janitor => (
    is      => 'ro',
    isa     => 'Replay::Janitor',
    builder => '_build_janitor',
    lazy    => 1
);

has reducer => (
    is      => 'ro',
    isa     => 'Replay::Reducer',
    builder => '_build_reducer',
    lazy    => 1,
);

sub _build_reducer {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my $self           = shift;
    my $event_system   = $self->eventSystem;
    my $rule_source    = $self->ruleSource;
    my $storage_engine = $self->storageEngine;

    my $reduce = Replay::Reducer->new(
        eventSystem   => $event_system,
        ruleSource    => $rule_source,
        storageEngine => $storage_engine
    );
    return $reduce;
}

has mapper => (
    is      => 'ro',
    isa     => 'Replay::Mapper',
    builder => '_build_mapper',
    lazy    => 1,
);

sub _build_mapper {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my $self           = shift;
    my $event_system   = $self->eventSystem;
    my $rule_source    = $self->ruleSource;
    my $storage_engine = $self->storageEngine;

    my $mapper = Replay::Mapper->new(
        eventSystem   => $event_system,
        ruleSource    => $rule_source,
        storageEngine => $storage_engine
    );
    return $mapper;
}

has worm => (
    is      => 'ro',
    isa     => 'Replay::WORM',
    builder => '_build_worm',
    lazy    => 1,
);

sub _build_worm {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my $self         = shift;
    my $config       = $self->config;
    my $event_system = $self->eventSystem;
    my $worm
        = Replay::WORM->new( eventSystem => $event_system, config => $config,
        );
    return $worm;
}

has reporter => (
    is      => 'ro',
    isa     => 'Replay::Reporter',
    builder => '_build_reporter',
    lazy    => 1,
);

sub _build_reporter {    ## no critic (ProhibitUnusedPrivateSubroutines)
    my $self           = shift;
    my $event_system   = $self->eventSystem;
    my $rule_source    = $self->ruleSource;
    my $storage_engine = $self->storageEngine;
    my $report_engine  = $self->reportEngine;
    my $report         = Replay::Reporter->new(
        eventSystem   => $event_system,
        ruleSource    => $rule_source,
        storageEngine => $storage_engine,
        reportEngine  => $report_engine,
    );
    return $report;
}

1;

__END__

=pod 

=head1 NAME

Replay - A bitemporal finite state machine engine

=head1 VERSION

0.04

=head1 SYNOPSIS

This is the central configuration and instantiation module of the Replay system.

You can instantiate a Replay object with a list of rules and config

use Replay;

# minimum
my $replay = Replay->new(rules => [], config =>
        { QueueClass => 'Replay::EventSystem::Null', StorageMode => 'Memory' } );

# all options
my $replay = Replay->new(
    rules  => [ COUNTRULE->new ],
    config => {
        QueueClass => [ AWSQueue, Null ],
        systemPrefix => queueMode => [ native, AWS, RabbitMQ ],    # zeromq
        StorageMode => [ Memory, Mongo ],    # couchdb, postgres, mysql
        AWS => {
            Identity => {
                name   => 'webserver',
                access => 'not really a key',
                secret => 'not really a secret',
            },
            snsIdentity => 'webserver',
            snsService  => 'https://sns.us-east-1.amazonaws.com',
            sqsIdentity => 'webserver',
            sqsService  => 'https://sqs.us-east-1.amazonaws.com',
        },
        Mongo    => { host => port => username => password => },
        RabbitMQ => { host => port => username => password => },
    },
);

# by mentioning them, they become active in this process.  Weird right?
$replay->worm;
$replay->mapper;
$replay->reducer;
$replay->janitor;

package COUNTRULE;

use Moose;

override match => sub {
    warn "MATCH HIT";
    return 1;
};
override key_value_set => sub {
    return 1 => 1;
};
override reduce => sub {
    my ($signature, @state) = @_;
    my $first = shift @state;
    $first += $_ foreach @state;
    return $first;
};

...

=head1 CONFIGURATION AND ENVIRONMENT

Replay is instantiated with a 'config' key which has a key for 
each of its pieces, and each of those pieces have its own configuration.

=head1 DESCRIPTION

Replay is a rules engine designed to operate in a scalable manner, 
particularly for further development of one's application because
every rule only interacts with any other rule through message passing.

The lack of any single model which many business rules interact with
provides the unusual characteristics of this system in making it easy
to modify and extend as the application matures.

=head1 SUBROUTINES/METHODS

=head2 _build_rule_source

=head2 _build_event_system

=head2 _build_storage_engine

=head2 _build_reducer

=head2 _build_mapper

=head2 _build_worm

=head1 DIAGNOSTICS

Mostly, the log file consists of exception outputs for troubleshooting

Merely carping things out should cause them to end up in the log file

=head1 DEPENDENCIES

Probably the single most significant dependency is some operating 
implementation of the AnyEvent module.

=head1 INCOMPATIBILITIES

Probably with the brain of non-object oriented non-functional programmers
who have difficulty seeing beyond the paradigm of their previous
applications

=head1 AUTHOR

David Ihnen, C<< <davidihnen at gmail.com> >>

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

1;    # End of Replay

