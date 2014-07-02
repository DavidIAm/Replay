package Replay::BaseBusinessRule;

use Moose;

has eventSystem => (is => 'ro', isa => 'Replay::EventSystem',);

# mapper
# [string]
has name => (is => 'ro', required => 1,);

# [string]
has version => (is => 'ro', isa => 'Str', default => '1',);

# [boolean] function match ( message )
sub match {
    die "stub, implement match";
}

# [timeWindowIdentifier] function window ( message )
sub window {
    my ($self, $message) = @_;

    # probably going to do soemthing with ->effectiveTime or ->recievedTime
    return 'alltime';
}

# [list of Key=>message pairs] function keyValueSet ( message )
sub keyValueSet {
    die "stub, implement keyValueSet";
}

# storage
# [ compareFlag(-1,0,1) ] function compare ( messageA, messageB )
sub compare {
    return 0;
}

# reducer
# [arrayRef of messages] function reduce (key, arrayref of messages)
sub reduce {
    die "stub, implement reduce";
}

# bureaucrat
# [diff report] function fullDiff ( ruleA, Version, ruleB, Version )
has fullDiff => (is => 'ro', isa => 'CodeRef', required => 0,);

# secretary
# [formatted Report] function delivery ( rule, [ keyA => arrayrefOfMessage, ... ] )
has delivery => (is => 'ro', isa => 'CodeRef', required => 0,);

1;
