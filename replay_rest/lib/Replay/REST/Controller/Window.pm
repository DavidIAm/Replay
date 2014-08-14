package Replay::REST::Controller::Window;

use Mojo::Base 'Mojolicious::Controller';

use File::Slurp qw/read_dir/;
use File::Spec;

sub windowIndex {
    my $self    = shift;
    my $stash   = $self->stash;
    my $rootdir = $self->config->{ReportFileRoot};
    my $dir     = File::Spec->catdir($rootdir, $stash->{domain}, $stash->{rule},
        $stash->{version});
    if (-d $dir) {
        my @windows = grep { -d File::Spec->catdir($dir, $_) } read_dir($dir);
        $self->req->url->path->trailing_slash(1);    #force trailing slash
        if (@windows) {
            $self->render(
                json => {
                    windows => [
                        map {
                            {   domain  => $stash->{domain},
                                rule    => $stash->{rule},
                                version => $stash->{version},
                                window  => $_,
                                abs_url => $self->req->url->path($_)->to_abs,
                                rel_url => $_,
                            }
                        } @windows
                    ],
                }
            );
        }
        else {
            $self->render(
                json => {
                    error   => 'no windows available in this version',
                    domain  => $stash->{domain},
                    rule    => $stash->{rule},
                    version => $stash->{version},
                }
            );
        }
    }
    else {
        $self->render(
            json => {
                error   => 'no such version',
                domain  => $stash->{domain},
                rule    => $stash->{rule},
                rule    => $stash->{rule},
                version => $stash->{version},
            }
        );
    }
    return 1;
}

1;
1;
