package Replay::ReportEngine::Filesystem;
use Data::Dumper;

use Moose;
use Git::Repository;
use Carp qw/confess carp croak/;
use Fcntl qw(:DEFAULT :flock);
use Replay::ReportEngine::Filesystem::Entry;
use File::MimeInfo::Magic;
use YAML;
use File::Basename;
use File::Path;
use Hash::Merge;
use File::Glob ':globally';
use File::Spec;
use File::Copy;
use File::Slurp;
use List::Util qw/max/;
use Time::HiRes qw/usleep/;
use Try::Tiny;

with qw/Replay::BaseReportEngine/;

has parentdir =>
    (is => 'ro', isa => 'Str', builder => '_build_parentdir', lazy => 1);

has workdir => (
    is      => 'ro',
    isa     => 'Str',
    builder => '_build_workdir',
    clearer => 'clear_workdir',
    lazy    => 1
);

has ruleSource  => (is => 'ro', isa => 'Replay::RuleSource',  required => 1);
has eventSystem => (is => 'ro', isa => 'Replay::EventSystem', required => 1);
has storageEngine =>
    (is => 'ro', isa => 'Replay::StorageEngine', required => 1);

#requires qw/delivery summary globsummary freeze copydomain checkpoint/;

sub existing_entry {
    my ($self, $idkey, $revision) = @_;
    return Replay::StorageEngine::Filesystem::Entry->new(
        config   => $self->config,
        key      => $idkey,
        revision => $revision || 'latest',
    );
}

sub new_entry {
    my ($self, $idkey) = @_;
    my $e = Replay::StorageEngine::Filesystem::Entry->new(
        config   => $self->config,
        key      => $idkey,
        readonly => 0,
    );
    return $e;
}

sub deliver {
    my ($self, $idkey, $revision) = @_;
    my $entry = $self->existing_entry($idkey, $revision);
    return $entry->content;
}

sub set_latest {
    my ($self, $idkey, $revision) = @_;
    my $entry = $self->existing_entry($idkey, $revision);
    return $entry->set_latest;
}

sub petrify {
    my ($self, $idkey, $revision) = @_;
    return $self->existing_entry($idkey, $revision)->petrify;
}

sub delivery {
    my ($self, $idkey) = @_;

    my $entry = $self->new_entry($idkey);

    my ($meta, @state) = $self->storageEngine->fetchCanonicalState($idkey);

    my $handle = $entry->writehandle;
    my $rule   = $self->ruleSource->byIdKey($idkey);
    $rule->delivery($handle, $meta, @state);
    $handle->close;

    $entry->set_metadata($meta);

    return $entry->revision;
}

sub summary {
    my ($self, $idkey) = @_;

    $idkey->clear_key;
    my $filename = $self->filename($idkey, 'tmp');
    my ($file, $dirs) = fileparse($filename);
    mkpath $dirs unless -d $dirs;
    my @keys     = $self->keys($idkey);
    my @keyfiles = map {
        $self->filename(Replay::IdKey->new($idkey->marshall, key => $_), 'latest')
    } @keys;
    my @metadata
        = map { $self->metadata(Replay::IdKey->new($idkey->marshall, key => $_)) }
        @keys;
    my $merge = Hash::Merge->new('RETAINMENT_PRECEDENT');
    my $meta  = shift @metadata;
    while (scalar @metadata) {
        $meta = $merge->merge($meta, shift @metadata);
    }
    my $handle = $self->filewritehandle($filename);

    my $rule = $self->ruleSource->byIdKey($idkey);
    $rule->summary($handle, @keyfiles);
    $handle->close;

    # Complete the meta information for this report
    my $type      = File::MimeInfo::Magic::mimetype($filename);
    my $extension = File::MimeInfo::extensions($type);

    $self->modify_meta(
        $filename,
        sub {
            my ($existing) = @_;
            %{$meta} = %{$existing}, %{$meta},
                mimetype  => $type,
                extension => $extension;    # naive merge
        }
    );

    my $newfile = $self->filename($idkey, 'new');
    link $filename, $newfile;
}

sub checkpoint {
    my ($self, $checkpoint) = @_;

}
sub copydomain {
	die "no copydomain";
}
sub globsummary {
    my ($self, $idkey) = @_;

    $idkey->clear_window;
    $idkey->clear_key;

    my $filename = $self->filename($idkey, 'tmp');
    my ($file, $dirs) = fileparse($filename);
    mkpath $dirs unless -d $dirs;
    my @windows     = $self->windows($idkey);
    my @sumfiles = map {
        $self->filename(Replay::IdKey->new($idkey->marshall, window => $_), 'latest')
    } @windows;
    my @metadata
        = map { $self->metadata(Replay::IdKey->new($idkey->marshall, window => $_)) }
        @windows;
    my $merge = Hash::Merge->new('RETAINMENT_PRECEDENT');
    my $meta  = shift @metadata;
    while (scalar @metadata) {
        $meta = $merge->merge($meta, shift @metadata);
    }
    my $handle = $self->filewritehandle($filename);

    my $rule = $self->ruleSource->byIdKey($idkey);
    $rule->globsummary($handle, @sumfiles);
    $handle->close;

    # Complete the meta information for this report
    my $type      = File::MimeInfo::Magic::mimetype($filename);
    my $extension = File::MimeInfo::extensions($type);

    $self->modify_meta(
        $filename,
        sub {
            my ($existing) = @_;
            %{$meta} = %{$existing}, %{$meta},
                mimetype  => $type,
                extension => $extension;    # naive merge
        }
    );

    my $newfile = $self->filename($idkey, 'new');
    link $filename, $newfile;
}

sub subdirectory {
    my ($self, $idkey) = @_;
    return File::Spec->catdir($self->workdir, $idkey->domain, $idkey->name,
        $idkey->version, ($idkey->window ? ($idkey->window) : ()));
}

sub windows {
    my ($self, $idkey) = @_;
    my @windows;
    opendir DIRECTORY, File::Spec->catdir($self->subdirectory, '..', '..');
    while (my $entry = readdir DIRECTORY) {
        next if $entry =~ /^\./;
        my $d = File::Spec->catfile($self->subdirectory, '..', '..', $entry);
        push @windows, $entry if (-d $d);
    }
    $self->revert($idkey);
    return @windows;
}

sub keys {
    my ($self, $idkey) = @_;
    my @keys;
    my $subdir = $self->subdirectory($idkey);
    opendir DIRECTORY, $subdir;
    while (my $entry = readdir DIRECTORY) {
        next if $entry =~ /^\./;
        my $f = File::Spec->catfile($subdir, $entry);
        push @keys, $entry if (-f $f);
    }
    return map { (split ':')[0] } @keys;
}

sub _build_workdir {
    my ($self) = @_;
    my $workdir = File::Spec->catdir($self->parentdir,
        $self->config->{stage} . '-replay');
    mkpath $workdir unless -d $workdir;
    croak
        "Unable to assert existence of writable process directory $workdir"
        unless -d $workdir && -w $workdir;
    return $workdir;
}

sub _build_parentdir {
    my ($self) = @_;
    croak "We need a ReportFileRoot configuration"
        unless $self->config->{ReportFileRoot};
    my $parentdir = $self->config->{ReportFileRoot};
    mkpath $parentdir unless -d $parentdir;
    croak "Unable to assert existence of writable directory $parentdir"
        unless -d $parentdir && -w $parentdir;
    return $parentdir;
}


sub drop {
    my ($self) = @_;
    File::Path::rmtree($self->workdir) or die "Unable to delete tree";
}

use namespace::autoclean;

1;
