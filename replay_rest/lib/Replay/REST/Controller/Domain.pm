package Replay::REST::Controller::Domain;

use Mojo::Base 'Mojolicious::Controller';

use File::Slurp qw/read_dir/;
use File::Spec;

sub domainBridge {
    my $self = shift;
    my $hash = $self->stash;
    warn "BRIDGE DOMAIN";
}

sub domainIndex {
    my $self    = shift;
    my $hash    = $self->stash;
    my $dir     = $self->config->{ReportFileRoot};
    my @domains = grep { -d File::Spec->catdir($dir, $_) } read_dir($dir);
    $self->req->url->path->trailing_slash(1);    #force trailing slash
    if (-d $dir && @domains) {
        $self->render(
            json => {
                domains => [
                    map {
                        { domain => $_ abs_url => $self->req->url->path($_)->to_abs, rel_url => $_, }
                    } @domains
                ],
            }
        );
    }
    else {
        $self->render(json => { error => 'no domains available', where => '/', });
    }
    return 1;
}

1;
