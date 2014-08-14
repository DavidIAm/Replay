package Replay::REST::Controller::Key;

use Mojo::Base 'Mojolicious::Controller';

use File::Slurp qw/read_file read_dir/;
use File::Spec;

sub keyIndex {
    my $self    = shift;
    my $stash   = $self->stash;
    my $rootdir = $self->config->{ReportFileRoot};
    my $dir     = File::Spec->catdir(
        $rootdir,          $stash->{domain}, $stash->{rule},
        $stash->{version}, $stash->{window}
    );
    if (-d $dir) {
        my %keys;
        foreach (grep { -f File::Spec->catdir($dir, $_) } read_dir($dir)) {
            push @{ $keys{ (split /\./)[0] } } => (split /\./)[1];
        }
        foreach (keys %keys) {
            no warnings 'numeric';
            if (grep { $_ eq 'latest' } @{ $keys{$_} }) {
                @{ $keys{$_} } = grep { $_ + 0 eq $_ } @{ $keys{$_} };
            }
            else {
                delete $keys{$_};
            }
            use warnings 'numeric';
        }

        $self->req->url->path->trailing_slash(1);    #force trailing slash
        if (%keys) {
            $self->render(
                json => {
                    revisions => [
                        map {
                            {   domain  => $stash->{domain},
                                rule    => $stash->{rule},
                                version => $stash->{version},
                                window  => $stash->{window},
                                key     => $_,
                                abs_url => $self->req->url->path($_)->to_abs,
                                rel_url => $_,
                            }
                        } keys %keys
                    ],
                }
            );
        }
        else {
            $self->render(
                json => {
                    error   => 'no keys available in this window',
                    domain  => $stash->{domain},
                    rule    => $stash->{rule},
                    version => $stash->{version},
                    window  => $stash->{window},
                }
            );
        }
    }
    else {
        $self->render(
            json => {
                error   => 'no such key',
                domain  => $stash->{domain},
                rule    => $stash->{rule},
                rule    => $stash->{rule},
                version => $stash->{version},
                window  => $stash->{window},
            }
        );
    }
    return 1;
}

1;
