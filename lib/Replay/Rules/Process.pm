package Replay::Rules::EDIProcess;

# This state encompasses the standing requests to raise a request
# on the zoho system

use Moose;
use CargoTel::EDI;
use Replay::Message;
use Readonly;
use Try::Tiny;

extends 'Replay::BusinessRule';

Readonly my $MAX_ATTEMPTS => 5;

has '+name' => (default => 'EDIProcess');

has '+version' => (default => '1');

sub match {
    my ($self, $message) = @_;
    warn("in Match MessageType=". $message->{MessageType});
    return 1 if $message->{MessageType} eq 'EDIProcess';
    return 1 if $message->{MessageType} eq 'EDIProcessResult';
    return 0;
}

sub keyValueSet {
    my ($self, $message) = @_;
    return 'allkey' => $message;
}

sub compare {
    my ($self, $a, $b) = @_;
    warn("JPS ah these jewls Do i Compare ");
    return do {
        my $first  = exists $a->{effectiveTime} || exists $a->{receivedTime} || 0;
        my $second = exists $b->{effectiveTime} || exists $b->{receivedTime} || 0;
        $first <=> $second;
        } unless ($a->{uuid} || $a->{message}->{requestUuid})
        cmp($b->{uuid} || $b->{message}->{requestUuid});
}

sub reduce {
    my ($self, $emitter, @atoms) = @_;
    my @continuation
        = @atoms;    # the atom list we'll be left with at the end of the reduce
    warn "\nREDUCE IN PROCESS FOR " . $self->name . "\n";

    # eliminate success pairs.
    foreach my $i (0 .. $#atoms) {
        my $flag = 0;
        if ($atoms[$i]->{MessageType} eq 'EDIProcessResult') {
warn "SUCCESS FOUND, ELIMINATING THIS AND " . $atoms[$i]->{message}{requestUuid};
            @continuation = grep {
                $_->{uuid} ne $atoms[$i]->{message}{requestUuid}
                    && $_->{uuid} ne $atoms[$i]->{uuid}
            } @continuation;
            $emitter->emit(
                Replay::Message->new(MessageType => 'CRMRaiseSuccess', Message => $atoms[$i])
            );
        }
    }

		#}}}

		my @out = ();
		foreach my $message (@continuation) {

        use Data::Dumper;
			warn "PROCESSING MESSAGE" . Dumper $message;
        if ($MAX_ATTEMPTS < scalar @{ $message->{attempts} || [] }) {
            warn "\nMAX ATTEMPTS EXCEEDED\n";
            $emitter->emit(
                Replay::Message->new(MessageType => 'CRMRaiseFailed', Message => $message));
            next;
        }

        push @out, $message;
        my $proc = $message->{Message};
        warn "\nThe Stream is: $proc->{Stream}\n";
        next unless $proc->{Stream};

        try {
            warn "\nOPENING SOURCE";
            my $source = CargoTel::EDI->open_source(
                $proc->{Driver}, $proc->{Source},
                $proc->{Subscriber}, { emitter => $emitter }
            );
            warn "\nNEW STREAM " . $proc->{Stream} . " params " . Dumper $proc->{Params};
            my $stream = $source->new_stream($proc->{Stream} => $proc->{Params});

            my $response = $stream->process();
            warn "\nRESPONSE FROM PROCESS: " . $response->status_line;
						warn "REsPONSE: ".Dumper $response unless $response->is_success;

            if ($response->code == 200) {
                $emitter->emit('origin',
                    Replay::Message->new(
                        MessageType => 'EDIProcessResult',
                        Message     => {
                            response    => $response->content,
                            message     => $proc,
                            requestUuid => $message->{uuid}
                        },
                    )
                );
            }
            else {
                push @{ $message->{attempts} || [] },
                    { epoch => time, response => $response };
            }
        }
        catch {
            warn "Exception while reducing the EDIProcess:" . $_;
            $emitter->emit(
                Replay::Message->new(
                    MessageType => 'EDIProcessException',
                    Message     => {
                        rule      => $self->name,
                        version   => $self->version,
                        exception => "$_",
                        message   => $message
                    }
                )
            );
        };
    }
    return @out;
}

1;
