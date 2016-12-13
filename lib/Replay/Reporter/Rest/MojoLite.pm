#!/usr/bin/env perl
package Replay::Reporter::Rest::MojoLite;

use Mojolicious::Lite;
use HTTP::Status qw(:constants :is status_message);

use Replay;
use Data::Dumper;
use Replay::IdKey::Loose;
use JSON;
use YAML;

our $VERSION = '0.04';

BEGIN { carp '---------------' }

my $replay = Replay->new(
    config => {
        EventSystem   => { Mode => 'Null' },
        StorageEngine => { Mode => 'Memory' },
        ReportEngine =>
            { Mode => 'Filesystem', reportFilesystemRoot => './reports', },

        timeout => 50,
        stage   => 'testscript-01-' . $ENV{USER},
    },
    rules => []
);

my $report_engine = $replay->reporter;

app->stash(
    domain  => 1,
    name    => 1,
    version => 1,
    window  => 1,
    key     => 1,
    rev     => 1
);

under '/replay/reports';    #should be in Config

get '/domain/:domain'
    . '/rule/:name'
    . '/version/:version'
    . '/window/:window'
    . '/key/:key'
    . '/rev/:rev' => {
    domain  => 'empty',
    name    => 'empty',
    version => 'empty',
    window  => 'empty',
    key     => 'empty',
    rev     => 'empty'
    } => my $reportgetter = sub {
    my $c = shift;
    if ( $c->req->query_params->param('rev') ) {
        $c->stash( 'rev', $c->req->query_params->param('rev') );
    }

    my $idkey = idkey_from_stash($c);

    if ( $idkey->has_key && $c->stash('rev') ne 'empty' ) {
        my $r = $report_engine->reportEngine->engine->current($idkey);
        if ( $c->stash('rev') eq 'latest' ) {
            if ( defined $r ) {
                return $c->redirect_to( $c->url_for->query($r) );
            }
            return $c->render(
                text => 'No current report available (you requested latest)',
                status => HTTP_NOT_FOUND
            );
        }

        # TODO branch for index or doocument
        #
        my $data = $report_engine->reportEngine->engine->retrieve( $idkey,
            $c->param('structured') );
        return $c->render(
            text   => 'The report is empty',
            status => HTTP_NOT_FOUND
        ) if $data->{EMPTY};
        my $type = $data->{TYPE};
        if ( $c->param('structured') ) {
            carp 'STRUCTURED MODE';
            return $c->respond_to(
                xml  => sub { $c->render( xml  => $data->{DATA} ) },
                json => sub { $c->render( json => $data->{DATA} ) },
                text => sub { $c->render( text => Dumper( $data->{DATA} ) ) },
                any => sub {
                    $c->res->headers->content_type('text/plain');
                    $c->render( text => YAML::Dump $data->{DATA} );
                },
            );
        }
        else {
            carp 'FORMATTED MODE';
            return $c->respond_to(
                any => sub {
                    $c->render( data => $data->{FORMATTED} );
                },
            );
        }
    }

    my $subs = $report_engine->reportEngine->engine->subkeys($idkey);
    if ( 0 < scalar @{$subs} ) {
        return $c->render(

            text => 'No such '
                . $report_engine->reportEngine->engine->directory($idkey)
                . ' report information found for '
                . $idkey->full_spec
                . to_json $subs,
            status => HTTP_NOT_FOUND
        );
    }
    my @keys    = qw/domain name version window key rev/;
    my %urlbits = ();
    while ( scalar @keys ) {
        last if $c->stash( $keys[0] ) eq 'empty';
        carp "STASH OF $keys[0] IS " . $c->stash( $keys[0] );
        my $key = shift @keys;
        carp "Cheking $key ( " . $c->stash($key);
        $urlbits{$key} = $c->stash($key);
    }
    my $this = shift @keys;

    sub sub_to_url {
        my $sub = shift;
        carp "THIS IS $this SUB IS $sub (" . Dumper \%urlbits;
        urlbits {$this} = $sub;
        my $url = $c->url_for( \%urlbits );
        if ( $this eq 'rev' ) {
            $url->query( rev => $sub );
        }
        return $url->to_abs->to_string;
    }

    my $data = [ map { sub_to_url($_) } @{$subs} ];

    return $c->render(
        xml  => { xml  => $data },
        json => { json => $data },
        text => { text => YAML::Dump($data) },
        any  => sub {
            carp 'ANY RENDER';
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

sub normalize {
    my ( $c, $key ) = @_;
    return if $c->stash($key) eq 'empty';
    if ( $key eq 'rev' ) {
        return if $c->stash($key) eq 'latest';
        return revision => $c->stash($key);
    }
    return $key => $c->stash($key);
}

sub idkey_from_stash {
    my $c = shift;
    my ( $domain, $name, $version, $window, $key, $rev ) = (
        $c->stash('domain'),  $c->stash('name'),
        $c->stash('version'), $c->stash('window'),
        $c->stash('key'),     $c->stash('rev'),
    );
    return Replay::IdKey::Loose->new(
        normalize('name'),   normalize('version'),
        normalize('window'), normalize('key'),
        normalize('rev'),    normalize('domain'),
    );
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
