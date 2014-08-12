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

# Construct a new Entry object for a report that already exists
sub existing_entry {
    my ($self, $idkey, $revision) = @_;
    return Replay::StorageEngine::Filesystem::Entry->new(
        config   => $self->config,
        key      => $idkey,
        revision => $revision || 'latest',
    );
}

# Construct a new Entry object for a report that does not yet exist
sub new_entry {
    my ($self, $idkey) = @_;
    my $e = Replay::StorageEngine::Filesystem::Entry->new(
        config   => $self->config,
        key      => $idkey,
        readonly => 0,
    );
    return $e;
}

sub url {
    my ($self, $idkey) = @_;
    die "configure ReportRESTBaseURL" unless $self->config->{ReportRESTBaseURL};
    my $baseurl = URI->new($self->config->{ReportRESTBaseURL});
my $entry = $self->existing_entry($idkey, $idkey->revision);
    my $url = URI->new_abs($entry->subdirectory . '/'. $entry->filename, $baseurl)->as_string;
warn "URL is $url";
return $url;
}

# TODO: is this the responsibility of the report engine?
sub deliver {
    my ($self, $idkey, $revision) = @_;
    my $entry = $self->existing_entry($idkey, $revision);
    return $entry->content;
}

sub summary {
    my ($self, $idkey) = @_;
    my $entry = $self->existing_entry($idkey);
    return $entry->content;
}

# report system procedures

sub checkpoint {
my ($idkey, $checkpointidentifier) = @_;
   die "no checkpoint yet";
# TODO: freeze everything
}

sub copydomain {
my ($olddomain, $newdomain) = @_;
	die "no copydomain";
# TODO: copy the state of this domain to a new one
}

# make the specified revision the active latest revision
sub set_latest {
    my ($self, $idkey, $revision) = @_;
    my $entry = $self->existing_entry($idkey, $revision);
    return $entry->set_latest;
}

# make the specified revision the active latest revision
sub petrify {
    my ($self, $idkey, $revision) = @_;
    return $self->existing_entry($idkey, $revision)->petrify;
}

# render the report at a key level
# TODO: Rename as 'renderKey'
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

# render the report at a window level
# TODO: Rename as 'renderWindow'
sub summarize 
{
    my ($self, $idkey) = @_;
return;
}

# render the report at a rule-version level
# TODO: Rename as 'renderRuleVersion'
sub globsummary {
    my ($self, $idkey) = @_;
return;

    $idkey->clear_window;
    $idkey->clear_key;

    my $filename = $self->filepath($idkey, 'tmp');
    my ($file, $dirs) = fileparse($filename);
    mkpath $dirs unless -d $dirs;
    my @windows     = $self->windows($idkey);
    my @sumfiles = map {
        $self->filepath(Replay::IdKey->new($idkey->marshall, window => $_), 'latest')
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

    my $newfile = $self->filepath($idkey, 'new');
    link $filename, $newfile;
}

# return the subdirectory this content should reveal in
# TODO: Rename as 'renderRuleVersion'
sub subdirectory {
    my ($self, $idkey) = @_;
    return File::Spec->catdir($idkey->domain, $idkey->name,
        $idkey->version, ($idkey->window ? ($idkey->window) : ()));
}

# list the window identifiers for a particular domain-rule-version
sub windows {
    my ($self, $idkey) = @_;
    my @windows;
    opendir DIRECTORY, File::Spec->catdir($self->workdir, $self->subdirectory, '..', '..');
    while (my $entry = readdir DIRECTORY) {
        next if $entry =~ /^\./;
        my $d = File::Spec->catfile($self->workdir, $self->subdirectory, '..', '..', $entry);
        push @windows, $entry if (-d $d);
    }
    $self->revert($idkey);
    return @windows;
}

# list the keys for a particular somain-rule-version-window
sub keys {
    my ($self, $idkey) = @_;
    my @keys;
    my $subdir = File::Spec->catdir($self->wordir, $self->subdirectory($idkey));
    opendir DIRECTORY, $subdir;
    while (my $entry = readdir DIRECTORY) {
        next if $entry =~ /^\./;
        my $f = File::Spec->catfile($subdir, $entry);
        push @keys, $entry if (-f $f);
    }
    return map { (split ':')[0] } @keys;
}

# construct the working directory from the configuration
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

# construct the parent directory from the configuration
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


# delete this workdirectory!  SUPER DANGEROUS!!!
sub drop {
    my ($self) = @_;
    File::Path::rmtree($self->workdir) or die "Unable to delete tree";
}

use namespace::autoclean;

1;
