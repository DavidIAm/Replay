package Replay::Role::BusinessRuleProxy;

use Moose::Role;
use Moose::Util::TypeConstraints;

with qw/Replay::Role::BusinessRule/;

our $VERSION = '0.02';

has eventSystem => (is => 'ro', isa => 'Replay::EventSystem',);
has reportEngine=> (is => 'ro', isa => 'Str',);

# mapper
# [string]
has idkey => (is => 'ro', isa => 'Replay::IdKey', required => 1,);

# [string]
has version => (is => 'ro', isa => 'Str', default => '1',);

has inquiry => ( is => 'ro', isa => 'HashRef[]', builder => '_build_inquiry',);
has report_disposition => (is => 'ro', isa => 'Item', builder => '_build_disposition',);
has optional_flag => ( is => 'ro', isa => 'HashRef[]', builder => '_build_optionals',);

requires qw/inquire execute/;

sub _build_inquiry {
  my ($self) = @_;
  return $self->inquire();
}

sub _build_optionals {
  my ($self) = @_;
  return { map { $_ => 1 } qw/delivery summary globsummary/ };
}

sub _build_disposition {
  my ($self) = @_;
  return $self->inquiry->{report_disposition};
}

# overload the can check to short circuit our communication
around 'can' => sub {
  my ($orig, $self, $method) = @_;
  return $self->inquiry->{$method} ? 1 : 0 if defined $self->optional_flag($method);
  return $self->$orig($method);
};

# THE BUSINESS RULE INTERFACE
sub match {
  my ($self, $message) = @_;
  return $self->execute('match', [$message])->{state}->[0];
}

sub key_value_set {
  my ($self, $message) = @_;
  return $self->execute('key_value_set', [$message])->{state}->[0];
}

sub window {
  my ($self, $message) = @_;
  return $self->execute('window', [$message])->{state}->[0];
}

sub compare {
  my ($self, $aa, $bb) = @_;
  return $self->execute('compare', [$aa, $bb])->{state}->[0];
}

sub reduce {
  my ($self, $emitter, @state) = @_;
  my $result = $self->execute([@state]);
  if ($result->{success}) {
    foreach my $message (@{$result->{events}}) {
      die unless $message->isa('Replay::Message');
      $emitter->emit($message);
    }
    return @{$result->{state}}
  }
  die $result->{error};
}

sub delivery {
  my ($self, @state) = @_;
  return @{$self->execute('delivery', [@state])->{state}} if $self->capable('delivery');
}

sub summary {
  my ($self, @state) = @_;
  return @{$self->execute('summary', [@state])->{state}} if $self->capable('summary');
}

sub globsummary {
  my ($self, @state) = @_;
  return @{$self->execute('globsummary', [@state])->{state}} if $self->capable('globsummary');
}

# [boolean] function match ( message )
# [timeWindowIdentifier] function window ( message )
#
# used by mapper
# [list of Key=>message pairs] function key_value_set ( message )
#
# used by reducer
# [arrayRef of messages] function reduce (key, arrayref of messages)
#
# used by storage
# [ compareFlag(-1,0,1) ] function compare ( messageA, messageB )
#
# used by bureaucrat
# [diff report] function fullDiff ( ruleA, Version, ruleB, Version )
has fullDiff => (is => 'ro', isa => 'CodeRef', required => 0,);

# used by clerk
# [formatted Report] function delivery ( rule, [ keyA => arrayrefOfMessage, ... ] )
# [formatted summary] function summary ( rule, [ keyA => arrayrefOfMessage, ... ] )
# [formatted globsummary] function globsummary ( rule, [ keyA => arrayrefOfMessage, ... ] )
#
1;

__END__

=pod

=head1 NAME

Replay::Role::BusinessRuleProxy

=head1 VERSION

Version 0.03

=head1 SYNOPSIS

Business rule proxy role

It is expected that this will be used in conjunction with a RuleSource to 
instantiate a series of proxy objects which can be used to communicate with
rule logic processors through some sort of a connection

package TESTRULEPROXY;

with 'Replay::Role::BusinessRuleProxy';

has 'rule' => (is => 'ro',);
has 'version' => (is => 'ro',);
has 'connection' => (is => 'ro', 
  isa => 'PipeServiceConnector',
  builder => '_build_pipeconnect',
  lazy => 0,
);

sub _build_pipeconnect {
  return new RPCServiceConnector;
}

# inquire() is expected to return something with these four keys.
# disposition is used by the current StorageEngineSelector
sub inquire {
  my ($self) = @_;
  my $map = $self->connection->methodmap(rule => $self->rule, version => $self->version);
  return { 
    delivery => exists $map->{delivery},
    summary => exists $map->{summary},
    globsummary => exists $map->{globsummary},
    report_disposition => '1',
  };
}

# execute() passes through data to the remote process or system to
# actually execute the business rule components
# ->execute('method', [@state]) is expected to return a hash like this
# { 
# state => [ RESULTING LIST OF STATE ], 
# events => [ bless({MessageType=>'message'}, 'Replay::Message') ]
# }
# OR die with something suitably informative.
sub execute {
  my ($self, $method, $state) = @_;
  getRuleCodeRef($method)->(@{$state});
}

=head1 SUBROUTINES/METHODS

This is fulfilling the Replay::Role::BusinessRule requirements so that
the proxy implimentor doesn't have to.

=head2 can

overloads UNIVERSAL::can when called on this process to use the state of the 
inquiry to determine whether certain optional methods should show as available

=head2 _build_inquiry

calls the implimentor's inquire function to cache the data for this rule

=head2 _build_optionals

figues out using the inquired data whether or not the reporting functions
are available to the utilizer

=head2 _build_disposition

cache the state of the disposition from the inquiry

=head2 match

delegate to implementor ->execute('match', ...)

=head2 key_value_set

delegate to implementor ->execute('key_value_set', ...)

=head2 window

delegate to implementor ->execute('window', ...)

=head2 compare

delegate to implementor ->execute('compare', ...)

=head2 reduce

delegate to implementor ->execute('reduce', ...)

=head2 delivery

delegate to implementor ->execute('delivery', ...)

=head2 summary

delegate to implementor ->execute('summary', ...)

=head2 globsummary

delegate to implementor ->execute('globsummary', ...)

=head1 UTILIZER METHODS

=head2 inquire

Do what you need to do to determine whether the reporting functions are 
available and indicate the disposition state.

=head2 execute

get the result of executing the portion of the rule named by the first 
parameter, with the sate of the rest.  Should return a hashref with key 'state'
in all cases, when processing the 'reduce' method must also return 'events'.

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

