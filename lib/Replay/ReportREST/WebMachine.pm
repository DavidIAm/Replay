use Web::Machine;

use strict;
use warnings

{
package Replay::ReportREST::Mojo;
BEGIN { warn '---------------' }


use parent 'Web::Machine::Resource';

sub content_types_provided {
    [
        { 'text/plain'       => 'to_plain', },
        { 'application/json' => 'to_json', },
        { 'application/xml'  => 'to_xml', },
        { 'text/yaml'        => 'to_yaml' },

    ];
}

sub to_plain {
}

sub to_yaml {
}

sub to_xml {
}

sub context {
    my $self = shift;
    $self->{idkey} = idkey_from_list( @_ );
    $self->{'context'} ||= $replay->reporter->reportEngine->engine->retrieve( $idkey,
            structured => $self->request->query_parameters->{'structured'} );


    return $self->{'context'};
}

sub allowed_methods {
    return [
        qw[ GET HEAD PUT POST ],
        ( (shift)->request->path_info eq '/' ? () : 'DELETE' )
    ];
}

sub map_to_data {
  my $self = shift;
    if ( $self->{idkey}->has_key && $self->{idkey}->has_rev) {
        if ( $c->{idkey}->indicate_latest_rev ) {
        }
    }
  }
sub resource_exists {
    my $self = shift;

    $self->context(bind_path( '/reports/domain/:domain/rule/:name/version/:version/window/:window/key/:key/rev/:rev', $self->request->path_info));

    return ! $self->context->{EMPTY};
}

sub to_json { 
  $JSON->encode( (shift)->context->{DATA} ) 
}

sub from_json {
    my $self = shift;
    my $data = $JSON->decode( $self->request->content );

}

sub my_report {
my $self = shift;
return $self->{my_report};
}

sub report_retriever {
    my $c = shift;
    $c->stash( 'rev', $c->req->query_params->param('rev') )
      if $c->req->query_params->param('rev');
    $c->stash( 'current', undef );
    my $idkey = idkey_from_list($c);

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

sub idkey_from_list {
    my ( $domain, $name, $version, $window, $key, $rev ) = @_;
    try {
        return Replay::IdKey::Loose->new(
            {
                ( defined $name    ? ( name    => $name )    : () ),
                ( defined $version ? ( version => $version ) : () ),
                ( defined $window  ? ( window  => $window )  : () ),
                ( defined $key     ? ( key     => $key )     : () ),
                (
                    defined $rev && $rev ne 'latest' ? ( revision => $rev ) : ()
                ),
                ( defined $domain ? ( domain => $domain ) : () ),
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

## Please see file perltidy.ERR
## Please see file perltidy.ERR
