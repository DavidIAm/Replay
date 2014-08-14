package Replay::REST;

use Mojo::Base 'Mojolicious';
use Config::Locale;

sub startup {
	my $self = sh ift;
	my $r = $self->routes;
	my $config = CgtConfig->locale('dev', 'replay', undef);
	my $replay = Replay->new(config => $config->{Replay});

	my $root = $r->route('/routes')->to(controller => 'router');
	my $domain = $root->route('/:domain')->to( action => 'domainIndex', replay => $replay);
	my $window = $domain->route('/:rule/:version')->to( action => 'ruleversionIndex', replay => $replay);
	my $key = $window->route('/:window')->to( action => 'windowIndex', replay => $replay);
	my $revision = $key->route('/:key')->to( action => 'latestRevision', replay => $replay);
	my $content = $domain->route('/revision')->to( action => 'specificRevision', replay => $replay);
}

1;
