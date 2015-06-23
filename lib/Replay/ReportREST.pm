#!/usr/bin/env perl
package Replay::ReportREST;
BEGIN { warn '---------------' }

use Mojolicious::Lite;
use HTTP::Status qw(:constants :is status_message);

use Replay;
use Data::Dumper;
use Replay::IdKey;
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
    revision => 1
);

under '/replay/reports/alpha';

get '/:name/:version/:window/:key/:rev' => { rev => 'revisions' } => sub {
  # if rev is 'latest'
  # if rev is 'revisions'
  # if rev is a revision number (integer)
};
get '/:name/:version/:window/:rev' => { rev => 'revisions' } => sub {
  # if rev is 'latest'
  # if rev is 'revisions'
  # if rev is a revision number (integer)
};
get '/:name/:version/:rev' => { rev => 'revisions' } => sub {
  # if rev is 'latest'
  # if rev is 'revisions'
  # if rev is a revision number (integer)
};
get '/:name/:rev' => { rev => 'revisions' } => sub {
  # if rev is 'latest'
  # if rev is 'revisions'
  # if rev is a revision number (integer)
};
get '/:rev' => { rev => 'revisions' } => sub {
  # if rev is 'latest'
  # if rev is 'revisions'
  # if rev is a revision number (integer)
};

get '/:name/:version/:window/:key/:rev' => {
    domain  => 'default',
    name    => 'trash',
    version => '0.1',
    window  => undef,
    key     => undef,
    rev     => undef
  } => sub {
    my $c     = shift;
    my $idkey = Replay::IdKey->new(
        {
            ( $c->stash('name')    ? ( name    => $c->stash('name') )    : () ),
            ( $c->stash('version') ? ( version => $c->stash('version') ) : () ),
            ( $c->stash('window')  ? ( window  => $c->stash('window') )  : () ),
            ( $c->stash('key')     ? ( key     => $c->stash('key') )     : () ),
            (
                $c->stash('rev')
                ? ( revision => $c->stash('rev') )
                : ()
            ),
        }
    );
    my $data = $reportEngine->reportEngine->engine->retrieve($idkey);
    return $c->render(text => "No report available", status => HTTP_NOT_FOUND) if $data->{EMPTY};
    $c->respond_to(
        xml  => sub { $c->render(xml => $data) },
        json => sub { $c->render(json => json => { to_json $data }) },
        text => sub { $c->render(text => Dumper $data) },
        any  => sub { 
          $c->res->headers->content_type('text/x-yaml');
          $c->render(text => YAML::Dump $data); },
    );
  };

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
