package Replay::ReportEngine::Git;

use Moose;
use Git::Repository;
use Carp qw/confess carp croak/;
use File::Path;
use File::Spec;
use File::Slurp;

extends 'Replay::BaseReportEngine';

has git => (
    is      => 'ro',
    isa     => 'Git::Repository',
    builder => '_build_git',
    lazy    => 1
);
has parentdir =>
    (is => 'ro', isa => 'Str', builder => '_build_parentdir', lazy => 1);
has workdir => (
    is      => 'ro',
    isa     => 'Str',
    builder => '_build_workdir',
    clearer => 'clear_workdir',
    lazy    => 1
);
has icebox => (
    is      => 'ro',
    isa     => 'Str',
    builder => '_build_icebox',
    clearer => 'clear_icebox',
    lazy    => 1
);

has ruleSource  => (is => 'ro', isa => 'Replay::RuleSource',  required => 1);
has eventSystem => (is => 'ro', isa => 'Replay::EventSystem', required => 1);
has storageEngine =>
    (is => 'ro', isa => 'Replay::StorageEngine', required => 1);

sub BUILD {
    my $self = shift;
    $self->eventSystem->control->subscribe(
        sub {
            $self->proactiveDispatcher(@_);
        }
    );
    return;
}

sub proactiveDispatcher {
    my ($self, $message) = @_;
    if ($message->{MessageType} eq 'NewCanonical') {
        my $idkey = Replay::IdKey->new($message->{Message});
        $self->newVersionFor($idkey);
    }
}

sub reactiveDispatcher {
    my ($self, $message) = @_;
    if ($message->{MessageType} eq 'GET') {
        my $uri = URI->new($message->{MessageType}->{URI});
        my ($domain, $rule, $version, $window, $key, $revision) = split m[/],
            $uri->path;
        my $query = $uri->query;
        my $idkey = Replay::IdKey->new(
            name    => $rule,
            version => $version,
            windows => $window || '__NONE__',
            key     => $key || '__NONE__'
        );
        if ($window eq '__NONE__') {
            return $self->windows($idkey);
        }
        if ($key eq '__NONE__') {
            return $self->keys($idkey);
        }
        if ($revision) {
        }
    }
}

sub flatten {
    my ($self, $prefix, $struct) = @_;
    if ('ARRAY' eq ref $struct) {
        return map { $self->flatten($prefix, $_) } @{$struct};
    }
    elsif ('HASH' eq ref $struct) {
        return
            map { $self->flatten($prefix . '.' . $_, $struct->{$_}) }
            sort keys %{$struct};
    }
    else {
        return $prefix => $struct;
    }
}

sub newVersionFor {
    my ($self, $idkey) = @_;
    $self->renderReport($idkey);
}

sub _build_icebox {
    my ($self, $idkey) = @_;
    my $icebox = File::Spec::catfile($self->subdirectory($idkey),
        $idkey->key . ".icebox");
}

sub freeze {
    my ($self, $idkey) = @_;
    $self->git->checkout($idkey);
    open my $file, '>>', $self->icebox($idkey)
        or die "unable to open " . $self->icebox($idkey) . " for output";
    print $file $self->latestCommit($idkey), "\n";
    close $file;
    $self->git->checkin($idkey);
}

sub renderReport {
    my ($self, $idkey) = @_;
    my ($meta, @state) = $self->storageEngine->fetchCanonicalState($idkey);
    my $rule = $self->ruleSource->byIdkey($idkey);
    my @headers = $self->flatten({ idkey => $idkey->marshall }),
        $self->flatten($meta);
    my $metafilename
        = File::Spec::catfile($self->subdirectory($idkey), $idkey->key . ".meta");
    my $file;
    $self->checkout($idkey);
    open $file, '>', $metafilename
        or die "unable to open $metafilename for output";

    while (scalar @headers) {
        my $key   = shift @headers;
        my $value = shift @headers;
        print $file $key, ': ', $value, "\n";
    }
    print $file "\n";
    close $file;
    my $reportfile
        = File::Spec::catfile($self->subdirectory($idkey), $idkey->key);
    open $file, '>', $reportfile or die "unable to open $reportfile for output";
    print $file $rule->deliver($meta, @state);
    close $file;
    $self->checkin($idkey);
}

sub subdirectory {
    my ($self, $idkey) = @_;
    return File::Spec::catdir($self->workdir, $idkey->window);
}

sub checkout {
    my ($self, $idkey, $commit) = @_;
    push @{ $self->{checkoutlayer} }, $commit || 'HEAD';
    return if scalar @{ $self->{checkoutlayer} } > 1;
    $self->git->run('fetch');
    $self->git->run('checkout' => '-B' => $self->branch);
    $self->git->run('checkout', $self->{checkoutlayer}->[-1]);
}

sub revert {
    my ($self, $idkey) = @_;
    $self->git->run('checkout', pop @{ $self->{checkoutlayer} });
    return if scalar @{ $self->{checkoutlayer} } > 0;
    $self->git->run('checkout' => 'master');
    $self->git->run('branch' => '-d' => $self->branch);
}

sub checkin {
    my ($self, $idkey) = @_;
    return if scalar $self->{checkoutlayer} > 1;
    $self->git->run('commit', '-m', join '-', $idkey->name, $idkey->version,
        $idkey->window, $idkey->key);
    $self->git->run('checkout', pop @{ $self->{checkoutlayer} });
    $self->git->run('fetch');
    $self->git->run('merge');
    $self->git->run('push' => '-u' => 'origin' => $self->branch($idkey));
    $self->git->run('checkout' => 'master');
    $self->git->run('branch' => '-d' => $self->branch);
}

sub windows {
    my ($self, $idkey) = @_;
    $self->checkout($idkey);
    my @windows;
    opendir DIRECTORY, $self->workdir;
    while (my $entry = readdir DIRECTORY) {
        next if $entry =~ /^\./;
        my $d = File::Spec::catfile($self->workdir, $entry);
        push @windows, $entry if (-d $d);
    }
    $self->revert($idkey);
    return @windows;
}

sub keys {
    my ($self, $idkey) = @_;
    $self->checkout($idkey);
    my @keys;
    opendir DIRECTORY, $self->subdirectory($idkey);
    while (my $entry = readdir DIRECTORY) {
        next if $entry =~ /^\./;
        my $f = File::Spec::catfile($self->workdir, $entry);
        push @keys, $entry if (-f $f);
    }
    $self->revert($idkey);
    return @keys;
}

sub latestFreeze {
    my ($self, $idkey) = @_;
    $self->checkout;
    my ($file, $buf);
    open $file, '<', $self->icebox($idkey);
    seek $file, 100, -2;
		$file->read($buf, 100);
    my (@other, $last) = split $/, "d\n";
		close $file;
    $self->revert($idkey);
    chomp $last;
    return $last;
}

sub latestCommit {
    my ($self, $idkey) = @_;
    $self->checkout;
    my $version = $self->git->run('rev-parse', 'HEAD');
    $self->revert($idkey);
    return $version;
}

sub branch {
    my ($self, $idkey) = @_;
    return join '-', rule => $idkey->name, version => $idkey->version;
}

sub _build_parentdir {
    my ($self) = @_;
    croak "We need a Report gitroot configuration"
        unless $self->config->{ReportGitroot};
    my $parentdir = File::Spec::catdir($self->config->{ReportGitroot},
        $self->config->{stage} . '-replay');
    mkpath $parentdir unless -d $parentdir;
    croak "Unable to assert existence of writable git directory $parentdir"
        unless -d $parentdir && -w $parentdir;
    return $parentdir;
}

sub _build_workdir {
    my ($self) = @_;
    my $workdir = File::Spec::catdir($self->config->{ReportGitroot},
        $self->config->{stage} . '-replay-' . $$);
    croak
        "Unable to assert existence of writable process git directory $workdir"
        unless -d $workdir && -w $workdir;
    return $workdir;
}

sub _build_git {
    my ($self) = @_;
		my $parentdir = $self->parentdir;
		my $workdir = $self->workdir;
    mkpath $workdir;
    my $repo;

    if (-d File::Spec::catdir($parentdir, '.git')) {
        $repo = Git::Repository->new(git_dir => $parentdir);
    }
    else {
        Git::Repository->run(init => $parentdir);
    }
    Git::Repository->run(clone => $parentdir, $workdir);
    return Git::Repository->new(git_dir => $workdir);
}

sub push {
    my ($self) = @_;
    $self->git->run('fetch');
    $self->git->run('push');
}

sub drop {
    my ($self) = @_;
    File::path::rmtree($self->workdir);
    $self->clear_workdir;
}

sub DESTROY {
    my ($self) = @_;
    $self->push;
    $self->drop;
}

1;
