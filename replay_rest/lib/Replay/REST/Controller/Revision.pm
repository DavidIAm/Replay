package Replay::REST::Controller::Revision;

use Mojo::Base 'Mojolicious::Controller';

use File::MimeInfo::Magic;
use File::Slurp qw/read_file read_dir/;
use File::Spec;

sub latestRevisionDocument {
    my $self     = shift;
    my $revision = $self->stash('revision');
    if ($revision eq 'latest') {
        warn "LATEST";
        $revision = read_file($self->path) + 0;
    }
    $self->stash(revision => $revision);
    return $self->revisionDocument();
}

sub path {
    my $self    = shift;
    my $stash   = $self->stash;
    my $rootdir = $self->config->{ReportFileRoot};
    my $dir
        = File::Spec->catdir($stash->{domain}, $stash->{rule}, $stash->{version},
        $stash->{window});
    my $key      = $stash->{key};
    my $revision = $stash->{revision};

    my $filename = $key . '.' . $revision;
    return File::Spec->catfile($rootdir, $dir, $filename);
}

sub revisionDocument {
    my $self     = shift;
    my $stash    = $self->stash;
    my $rootdir  = $self->config->{ReportFileRoot};
    my $filepath = $self->path;
    $self->app->types->type('yaml' => 'application/x-yaml');
    if (-f $filepath) {

        my $type      = File::MimeInfo::Magic::mimetype($filepath);
        my $extension = File::MimeInfo::extensions($type);

        $self->render_file(
            filepath              => $filepath,
            format                => $extension,
            'content_disposition' => 'inline'
        );

    }
    else {
        $self->render(
            json => {
                error    => 'no such revision',
                filepath => $filepath,
                domain   => $stash->{domain},
                rule     => $stash->{rule},
                version  => $stash->{version},
                window   => $stash->{window},
                key      => $stash->{key},
                revision => $stash->{revision},
            }
        );
    }
    return 1;
}

sub revisionIndex {
    my $self    = shift;
    my $stash   = $self->stash;
    my $rootdir = $self->config->{ReportFileRoot};
    my $dir     = File::Spec->catdir(
        $rootdir,          $stash->{domain}, $stash->{rule},
        $stash->{version}, $stash->{window}
    );
    if (-d $dir) {
        my %keys;
        my $key = $stash->{key};
        foreach (grep { /^ $key \./x && -f File::Spec->catdir($dir, $_) }
            read_dir($dir))
        {
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
            my %revisions;
            foreach my $key (keys %keys) {
                my $latest = read_file(File::Spec->catfile($dir, $key . '.' . 'latest')) + 0;
                foreach my $revision (@{ $keys{$key} }) {
                    my $pegfile
                        = File::Spec->catfile($dir, $key . '.' . $revision . '.' . 'pegged');
                    push @{ $revisions{$key} },
                        {
                        domain   => $stash->{domain},
                        rule     => $stash->{rule},
                        version  => $stash->{version},
                        window   => $stash->{window},
                        key      => $key,
                        revision => $revision,
                        abs_url  => $self->req->url->path('r' . $revision)->to_abs,
                        rel_url  => 'r' . $revision,
                        latest   => ($latest eq $revision ? 1 : 0),
                        pegged   => (-f $pegfile ? 1 : 0),
                        };
                }
            }
            $self->render(
                json => { revisions => [ map { @{ $revisions{$_} } } keys %keys ], });
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
                error   => 'no such rule',
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

