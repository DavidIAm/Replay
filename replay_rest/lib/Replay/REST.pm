package Replay::REST;
use Mojo::Base 'Mojolicious';
use File::Slurp;
use Config::Locale;
use lib '/home/ubuntu/Replay/lib';
use Replay;

# This method will run once at server start
sub startup {
    my $self = shift;

    # Documentation browser under "/perldoc"
    $self->plugin('PODRenderer');
    $self->plugin('RenderFile');

    # Router
    my $r = $self->routes;

    # Config
    my $config = Config::Locale->new(
        identity  => [ read_file('/etc/STAGE', { chomp => 1 }), 'replay', undef ],
        directory => '/etc/cargotel/conf',
    )->config->{Replay};

    $self->secrets('ReplayRESTSecret' => [$config->{RESTSecret}]);
    push @{ $self->static->paths }, $config->{ReportFileRoot};
    $self->helper(config => sub { return $config });

    # Normal route to controller
    $r->get('/')->to('example#welcome');

    my $replay = Replay->new(config => $config, rules => []);
    $self->helper(replay => sub { return $replay });
    $r->get('/reports/')->to('domain#domainIndex');
    my $root = $r->get('/reports');
    $root->get('/:domain')->to('rule#ruleIndex');
    $root->get('/:domain/summary')->to('domain#summary');
    $root->get('/:domain/:rule')->to('version#versionIndex');
    $root->get('/:domain/:rule/summary')->to('domain#summary');
    $root->get('/:domain/:rule/v:version')->to('window#windowIndex');
    $root->get('/:domain/:rule/v:version/summary')->to('domain#summary');
    $root->get('/:domain/:rule/v:version/:window')->to('key#keyIndex');
    $root->get('/:domain/:rule/v:version/:window/summary')->to('domain#summary');
    $root->get('/:domain/:rule/v:version/:window/:key')
        ->to('revision#revisionIndex');
    $root->get('/:domain/:rule/v:version/:window/:key/latest')
        ->to('revision#latestRevisionDocument');
    $root->get('/:domain/:rule/v:version/:window/:key/r:revision)')
        ->to('revision#revisionDocument');

}

1;

