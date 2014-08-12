package Replay::StorageEngine::Filesystem::Entry;

use Data::Dumper;
use Moose;
use File::NFSLock;
use Data::UUID;
use Carp qw/croak carp cluck/;
use Fcntl qw(:DEFAULT :flock);
use File::Slurp;
use File::Path;

has config   => (is => 'ro', isa => 'HashRef', required  => 1);
has key      => (is => 'ro', isa => 'Replay::IdKey',   required  => 1);
has revision => (is => 'rw', isa => 'Str',     predicate => 'has_revision');
has readonly => (is => 'rw', isa => 'Bool',    default   => 1, writer => '_set_readonly');

has parentdir =>
    (is => 'ro', isa => 'Str', builder => '_build_parentdir', lazy => 1);
has uuid     => (
    is      => 'ro',
    isa     => 'Data::UUID',
    builder => '_build_uuid',
    clearer => 'clear_uuid',
    lazy    => 1
);

sub BUILD {
    my $self = shift;
    $self->revision($self->latest_revision)
        if $self->has_revision && $self->revision eq 'latest';
    $self->new_revision if !$self->has_revision && !$self->readonly;
    $self->revision(0) if !$self->has_revision && $self->readonly;
die "Couldn't figure out revision" unless $self->has_revision && defined $self->revision;
}

sub exists {
    my ($self) = @_;
    return -f $self->filepath;
}

sub new_revision {
    my $self = shift;
    $self->_lock('FORNEWREVISION');
    $self->revision($self->set_serial($self->get_serial + 1));
}

sub content {
    my $self = shift;
    return { __EMPTY__ => 1 }, undef unless $self->exists;
    return ($self->metadata, $self->readhandle);
}

sub metadata {
    my ($self) = @_;
    warn "NO META FOR NON EXISTANT" unless $self->exists;
    return YAML::LoadFile($self->metafile) if $self->exists;
    return {};
}

sub list_petrified {
    my ($self) = @_;
    my $lock = $self->_lock;
    return read_file($self->filepath . ".petrified", { chomp => 1 });
}

sub petrify {
    my ($self)  = @_;
    my $lock    = self->_lock;
    my @serials = read_file($self->filepath . ".petrified");    #within lock
    push @serials, $self->revision;
    return write_file($self->filepath . ".petrified", @serials);
}

sub filepath {
    my ($self, $custom) = @_;
    my $dir = File::Spec->catdir($self->workdir, $self->subdirectory);
    my $filepath = File::Spec->catfile($dir, $self->filename($custom));
    mkpath $dir unless -d $dir;
    croak "Unable to create directory $dir" unless -d $dir;
    return $filepath;
}

sub filename {
    my ($self, $custom) = @_;
    my $filename = join '.',
        ($self->key->key ? ($self->key->key) : ('rollup')),
        defined $custom ? $custom : $self->revision;
    return $filename;
}

sub get_serial {
    my ($self) = shift;
    return 0 unless -f $self->serial_file;
    return read_file($self->serial_file, { chomp => 1 }) + 0;
}

sub set_serial {
    my ($self, $serial) = @_;
die "Cannot set serial to undef" unless defined $serial;
    write_file($self->serial_file, $serial);
    return $serial;
}

sub set_latest {
    my $self = shift;
    $self->_set_readonly(1);
    return write_file($self->latest_file, $self->revision);
}

sub serial_file {
    my ($self) = @_;
    return $self->filepath('') . 'serial';
}
sub latest_file {
    my ($self) = @_;
    return $self->filepath('') . 'latest';
}

sub latest_revision {
    my ($self) = @_;
    return 0 unless -f $self->latest_file;
    return read_file($self->latest_file);
}

sub metafile {
    my $self = shift;
    return $self->filepath . '.meta';
}

sub set_metadata {
    my ($self, $metadata) = @_;
    croak "Cannot write when object readonly" if $self->readonly;
    my $lock = $self->_lock;
    YAML::DumpFile($self->metafile, { $self->derived_metadata, %{$metadata} })
        or croak "unable to write meta yaml file";
}

sub derived_metadata {
    my $self = shift;
    my ($type, $extension);
    open my $typecheck, '<', $self->filepath;
    my $buff;
    read($typecheck, $buff, 100);
    close $typecheck;

    # this is a yaml file
    if ($buff =~ /^---\n/m) {

        $type      = 'text/yaml';
        $extension = 'yaml';
    }

    # Complete the meta information for this report
    else {
        $type      = File::MimeInfo::Magic::mimetype($self->filepath);
        $extension = File::MimeInfo::extensions($type);
    }
    return (type => $type, extension => $extension);
}

sub readhandle {
    my ($self) = @_;
    return undef unless $self->exists;
    my $newfile = IO::File->new($self->filepath, 'r');
    croak "Unable to open file " . $self->filepath . " as readonly $! $? $@"
        unless $newfile;
    return $newfile;
}

sub _lock {
    my ($self, $custom) = @_;
    return File::NFSLock->new(
        {   file               => $custom || $self->filepath,
            lock_type          => LOCK_EX | LOCK_NB,
            blocking_timeout   => 10,
            stale_lock_timeout => 30 * 60,
        }
    );
}

sub subdirectory {
    my ($self) = @_;
    return File::Spec->catdir($self->workdir, $self->key->domain,
        $self->key->name, $self->key->version,
        ($self->key->window ? ($self->key->window) : ()));
}

sub workdir {
    my ($self) = @_;
    my $workdir = File::Spec->catdir($self->parentdir,
        $self->config->{stage} . '-replay');
    mkpath $workdir unless -d $workdir;
    croak
        "Unable to assert existence of writable process directory $workdir"
        unless -d $workdir && -w $workdir;
    return $workdir;
}

sub writehandle {
    my ($self) = @_;
    my $newfile = IO::File->new($self->filepath, 'w');
    croak "Unable to open file ".$self->filepath." as writeonly" unless $newfile;
    return $newfile;
}

sub new_uuid {
    my ($self) = @_;
    return $self->uuid->to_string($self->uuid->create);
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

sub _build_uuid {
    return Data::UUID->new;
}

sub _build_unique {
my ($self) = @_;
    return $self->uuid->to_string($self->uuid->create);
}

1;

