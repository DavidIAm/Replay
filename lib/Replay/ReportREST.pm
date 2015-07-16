#!/usr/bin/env perl
package Replay::ReportREST;
BEGIN { warn '---------------' }

use Mojolicious::Lite;
use HTTP::Status qw(:constants :is status_message);

use Replay;
use Data::Dumper;
use Replay::IdKey::Loose;
use JSON;
use YAML;

my $replay = Replay->new(
    config => {
        EventSystem   => { Mode => 'Null' },
        StorageEngine => { Mode => 'Memory' },
        ReportEngine  => {
            Mode                 => 'Filesystem',
            reportFilesystemRoot => './reports',
        },

        timeout => 50,
        stage   => 'testscript-01-' . $ENV{USER},
    },
    rules => []
);

$replay->worm;
$replay->reducer;
$replay->mapper;
my $reportEngine = $replay->reporter;

app->stash(
    domain   => 1,
    name     => 1,
    version  => 1,
    window   => 1,
    key      => 1,
    rev      => 1
);

under '/replay/reports';

get '/domain/:domain/rule/:name/version/:version/window/:window/key/:key/rev/:rev' => {
    domain  => 'empty',
    name    => 'empty',
    version => 'empty',
    window  => 'empty',
    key     => 'empty',
    rev     => 'empty'
  } => my $reportgetter = sub {
    my $c = shift;
    $c->stash( 'rev', $c->req->query_params->param('rev')) if $c->req->query_params->param('rev');
    my $idkey = idkey_from_stash($c);

    if ( $idkey->has_key && $c->stash('rev') ne 'empty') {
        my $r = $reportEngine->reportEngine->engine->current($idkey);
        if ( $c->stash('rev') eq 'latest' ) {
            if ( defined $r ) {
                return $c->redirect_to( $c->url_for->query($r) );
            }
            return $c->render(
                text   => "No current report available (you requested latest)",
                status => HTTP_NOT_FOUND
            );
        }

        # TODO branch for index or doocument
        #
        my $data = $reportEngine->reportEngine->engine->retrieve($idkey, $c->param('structured'));
        return $c->render(
                text   => "The report is empty",
                status => HTTP_NOT_FOUND
            ) if $data->{EMPTY};
        my $type = $data->{TYPE};
        if ($c->param('structured')) {
          warn "STRUCTURED MODE";
        return $c->respond_to(
            xml  => sub { $c->render( xml => $data->{DATA} ) },
            json => sub { $c->render( json => $data->{DATA} ) },
            text => sub { $c->render( text => Dumper($data->{DATA}) )},
            any  => sub {
                $c->res->headers->content_type('text/plain');
                $c->render( text => YAML::Dump $data->{DATA});
              },
          );
        } else {
          warn "FORMATTED MODE";
          return $c->respond_to(
            any  => sub {
                $c->render( data => $data->{FORMATTED});
            },
        );
      }
    }

    my $subs = $reportEngine->reportEngine->engine->subkeys($idkey);
    return $c->render(

        text => "No such "
          . $reportEngine->reportEngine->engine->directory($idkey)
          . " report information found for "
          . $idkey->full_spec
          . to_json $subs,
        status => HTTP_NOT_FOUND
    ) unless scalar @{$subs};
    my @keys    = qw/domain name version window key rev/;
    my %urlbits = ();
    while ( scalar @keys ) {
        last if $c->stash( $keys[0] ) eq 'empty';
        warn "STASH OF $keys[0] IS " . $c->stash( $keys[0] );
        my $key = shift @keys;
        warn "Cheking $key ( ". $c->stash($key);
        $urlbits{$key} = $c->stash($key);
    }
    my $this = shift @keys;
    my $e;

    my $data = [
        map {
            warn "THIS IS $this SUB IS $_ (" . Dumper \%urlbits;
            my $url = $c->url_for( $e = { %urlbits, $this => $_ } );
            $url->query( rev => $_ ) if $this eq 'rev';
            $url->to_abs->to_string;
        } @{$subs}
    ];
        warn Dumper $e;

    return $c->render(
        xml  => { xml => $data },
        json => { json => $data },
        text => { text => YAML::Dump($data) },
        any  => sub {
          warn "ANY RENDER";
            $c->res->headers->content_type('text/x-yaml');
            $c->render( text => YAML::Dump $data);
        },
    );

  };

get '/:domain/:name/:version/:window/:key' => {
    domain  => 'empty',
    name    => 'empty',
    version => 'empty',
    window  => 'empty',
    key     => 'empty',
    rev     => 'empty'
  } => $reportgetter;

sub idkey_from_stash {
    my $c = shift;
    my ( $domain, $name, $version, $window, $key, $rev ) = (
        $c->stash('domain'),  $c->stash('name'),
        $c->stash('version'), $c->stash('window'),
        $c->stash('key'),     $c->stash('rev')
    );
    try {
        return Replay::IdKey::Loose->new(
            {
                ( $name ne 'empty' ? ( name => $c->stash('name') ) : () ),
                (
                    $version ne 'empty'
                    ? ( version => $c->stash('version') )
                    : ()
                ),
                ( $window ne 'empty' ? ( window => $c->stash('window') ) : () ),
                ( $key    ne 'empty' ? ( key    => $c->stash('key') )    : () ),
                (
                         $rev ne 'empty'
                      && $rev ne 'latest' ? ( revision => $c->stash('rev') ) : ()
                ),
                ( $domain ne 'empty' ? ( domain => $c->stash('domain') ) : () ),
            }
        );
      }
    catch {};
}

app->start;

#use Mojo::Base -strict;

#$r->under(
#    '/replay/reports/' => sub {
#        my $c = shift;
#
#    }
#  )

#/replay/reports/:domain/:name/:version/:window/:key/:revision

#  $self->respond_to(
#    json => { status => $status, json => $response },
#    text => { status => $status, text => $message },
#    xml  => {
#        status => $status,
#        text   => XMLout(
#            $response,
#            NoAttr   => TRUE,
#            RootName => XML_ROOT,
#            keyattr  => [],
#            XMLDecl  => XML_DECL
#        )
#    },
#    any => {
#        status => HTTP_UNSUPPORTED_MEDIA_TYPE,
#        json   => status_message(HTTP_UNSUPPORTED_MEDIA_TYPE)
#    },
#  );
