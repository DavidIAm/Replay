package Replay::REST::Controller::Rule;

use Mojo::Base 'Mojolicious::Controller';

use File::Slurp qw/read_dir/;
use File::Spec;

sub ruleIndex {
    my $self    = shift;
    my $stash   = $self->stash;
    my $rootdir = $self->config->{ReportFileRoot};
    my $dir     = File::Spec->catdir($rootdir, $stash->{domain});
    if (-d $dir) {
        my @rules = grep { -d File::Spec->catdir($dir, $_) } read_dir($dir);
        $self->req->url->path->trailing_slash(1);    #force trailing slash
        if (@rules) {
            $self->render(
                json => {
                    rules => [
                        map {
                            {   domain => $stash->{domain},
                                rule   => $_,
                                abs_url => $self->req->url->path($_)->to_abs,
                                rel_url => $_,
                            }
                        } @rules
                    ],
                }
            );
        }
        else {
            $self->render(
                json => {
                    error => 'no rules available in this domain',
                    where => $stash->{domain},
                }
            );
        }
    }
    else {
        $self->render(
            json => { error => 'no such domain', what => $stash->{domain}, });
    }
    return 1;
}

1;
1;
