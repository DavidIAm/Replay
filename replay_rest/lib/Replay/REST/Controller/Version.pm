package Replay::REST::Controller::Version;

use Mojo::Base 'Mojolicious::Controller';

use File::Slurp qw/read_dir/;
use File::Spec;

sub versionIndex {
    my $self    = shift;
    my $stash   = $self->stash;
    my $rootdir = $self->config->{ReportFileRoot};
    my $dir     = File::Spec->catdir($rootdir, $stash->{domain}, $stash->{rule});
    if (-d $dir) {
        my @rules = grep { -d File::Spec->catdir($dir, $_) } read_dir($dir);
        $self->req->url->path->trailing_slash(1);    #force trailing slash
        if (@rules) {
            $self->render(
                json => {
                    rules => [
                        map {
                            {   domain  => $stash->{domain},
                                rule    => $stash->{rule},
                                version => $_,
                                abs_url => $self->req->url->path('v'.$_)->to_abs,
                                rel_url => 'v'.$_,
                            }
                        } @rules
                    ],
                }
            );
        }
        else {
            $self->render(
                json => {
                    error  => 'no versions available in this rule',
                    domain => $stash->{domain},
                    rule   => $stash->{rule},
                }
            );
        }
    }
    else {
        $self->render(
            json => {
                error  => 'no such rule',
                domain => $stash->{domain},
                rule   => $stash->{rule},
            }
        );
    }
    return 1;
}

1;
1;
