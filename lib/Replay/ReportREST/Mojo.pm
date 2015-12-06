#!/usr/bin/env perl
package Replay::ReportREST::Mojo;
BEGIN { warn '---------------' }

use Mojolicious::Lite;
use HTTP::Status qw(:constants :is status_message);

use Data::Dumper;
use Replay;
use Replay::IdKey::Loose;
use XML::Simple;
use JSON;
use YAML;

use Moose;

our $VERSION = '0.04';

#sub Replay {
#    return app->config('reportEngine');
#}

app->stash(
    domain  => 1,
    name    => 1,
    version => 1,
    window  => 1,
    key     => 1,
    rev     => 1
);

under '/replay/reports';

get
  '/domain/:domain/rule/:name/version/:version/window/:window/key/:key/rev/:rev'
  => {
    domain  => 'empty',
    name    => 'empty',
    version => 'empty',
    window  => 'empty',
    key     => 'empty',
    rev     => 'empty'
  } => \&report_retriever;

get '/:domain/:name/:version/:window/:key' => {
    domain  => 'empty',
    name    => 'empty',
    version => 'empty',
    window  => 'empty',
    key     => 'empty',
    rev     => 'empty'
} => \&report_retriever;


my $replay = Replay->new(
    config => {
        EventSystem   => { Mode         => 'Null' },
        StorageEngine => { Mode         => 'Memory' },
        Defaults       => { ReportEngine => 'Prime' },
        ReportEngines => [
            {
                Name => 'Prime',
                Mode => 'Filesystem',
                Root => './reports',
            },
        ],

        timeout => 50,
        stage   => 'testscript-01-' . $ENV{USER},
    },
    rules => []
);

sub report_retriever {
    my $c = shift;
    $c->stash( 'rev', $c->req->query_params->param('rev') )
      if $c->req->query_params->param('rev');
    $c->stash( 'current', undef );
    my $idkey = idkey_from_stash($c);

    my ($currentrecord) =
      $replay->reporter->reportEngine->engine->current($idkey);
    if ( $idkey->has_key && $c->stash('rev') ne 'empty' ) {
        if ( $c->stash('rev') eq 'latest' ) {
            if ( defined $currentrecord ) {
                return $c->redirect_to(
                    $c->url_for->query( rev => $currentrecord ) );
            }
            return $c->render(
                text   => "No current report available (you requested latest)",
                status => HTTP_NOT_FOUND
            );
        }

        # TODO branch for index or doocument
        #
        my $data =
          $replay->reporter->reportEngine->engine->retrieve( $idkey,
            $c->param('structured') );
        return $c->render(
            text   => "The report is empty",
            status => HTTP_NOT_FOUND
        ) if $data->{EMPTY};
        my $type = $data->{TYPE};
        if ( $c->param('structured') ) {
            warn "STRUCTURED MODE";
            return $c->respond_to(
                xml  => sub { $c->render( xml  => $data->{DATA} ) },
                json => sub { $c->render( json => $data->{DATA} ) },
                text => sub { $c->render( text => Dumper( $data->{DATA} ) ) },
                any  => sub {
                    $c->res->headers->content_type('text/plain');
                    $c->render( text => YAML::Dump $data->{DATA} );
                },
            );
        }
        else {
            warn "FORMATTED MODE";
            return $c->respond_to(
                any => sub {
                    $c->render( data => $data->{FORMATTED} );
                },
            );
        }
    }

    my $subs = $replay->reporter->reportEngine->engine->subkeys($idkey);

    use Data::Dumper;
    warn "SUBS: ($currentrecord) " . Dumper $subs;
    if ( grep { $_ eq $currentrecord } @{$subs} ) {
        $c->stash( 'current', $c->url_for->query( rev => $currentrecord ) );
    }

    return $c->respond_to(
        text => "No such "
          . $replay->reporter->reportEngine->engine->directory($idkey)
          . " report information found for "
          . $idkey->full_spec
          . to_json $subs,
        status => HTTP_NOT_FOUND
    ) unless scalar @{$subs};
    my @keys    = qw/domain name version window key rev/;
    my %urlbits = ();
    while ( scalar @keys ) {
        last if $c->stash( $keys[0] ) eq 'empty';
        my $key = shift @keys;
        $urlbits{$key} = $c->stash($key);
    }
    my $this = shift @keys;
    my $e;

    my $data = [
        map {
            my $url = $c->url_for( { %urlbits, $this => $_ } );
            $url->query( rev => $_ ) if $this eq 'rev';
            $url->to_abs->to_string;
        } @{$subs}
    ];

    $c->stash( listdata => $data );
    return $c->respond_to(
        xml  => { xml      => $data },
        json => {$data},
        text => { text     => YAML::Dump($data) },
        html => { template => 'indexlist' },
        any  => sub {
            warn "ANY RENDER";
            $c->res->headers->content_type('text/x-yaml');
            $c->render( text => YAML::Dump $data);
        },
    );

}

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
                    $version ne 'empty' ? ( version => $c->stash('version') )
                    : ()
                ),
                (
                    $window ne 'empty' ? ( window => $c->stash('window') )
                    : ()
                ),
                ( $key ne 'empty' ? ( key => $c->stash('key') ) : () ),
                (
                    $rev ne 'empty'
                      && $rev ne 'latest' ? ( revision => $c->stash('rev') )
                    : ()
                ),
                (
                    $domain ne 'empty' ? ( domain => $c->stash('domain') )
                    : ()
                ),
            }
        );
    }
    catch {};
}

app->start;

__DATA__

@@ indexlist.html.ep

<h3><a href="<%= $self->url_for("..") %>">Parent</a></h3>
% if (defined $current) {
<h3><a href="<%= $current %>">Current Report</a> (<a href="<%=$current%>&structured=1">DATA</a>)</h3>
% } else {
<h3>No current report</h3>
% }
<ul>Subkeys
% for my $entry (@{$listdata}) { 
 <li><a href="<%= $entry %>"><%= $entry %> </a>(<a href="<%=$entry%>&structured=1">DATA</a>)
% }
</ul>

@@ actualdata.html.ep

<a href="<%= $self->url_for("../") %>">Parent</a>
<ul>Subkeys
% for my $entry (@{$listdata}) {
 <li><a href="<%= $entry %>"><%= $entry %></a>
% }
</ul>

