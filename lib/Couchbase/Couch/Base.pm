# This module forms the CouchDB parts of
# Couchbase::Client's API

package Couchbase::Couch::Base;
use strict;
use warnings;
use Couchbase::Couch::Handle;
use Couchbase::Couch::HandleInfo;
use Couchbase::Couch::Design;
use Couchbase::Client::IDXConst;
use JSON::XS;
use JSON::SL;
use Data::Dumper;
use Log::Fu;


sub _CouchCtorInit {
    my ($cls,$av) = @_;
    $av->[CTORIDX_JSON_ENCODE_METHOD] = \&encode_json;
}

# The following methods are defined in Client.xs
# and alias to the memcached set() method, with
# special behavior for converting objects into
# JSON

# couch_store, couch_set
# couch_add
# couch_replace
# couch_cas

my %STRMETH_MAP = (
    GET => COUCH_METHOD_GET,
    POST => COUCH_METHOD_POST,
    PUT => COUCH_METHOD_PUT,
    DELETE => COUCH_METHOD_DELETE
);


# Returns a 'raw' request handle
sub couch_handle_raw {
    my ($self,$meth,$path,$body) = @_;
    my $imeth = $STRMETH_MAP{$meth};
    if (!defined $imeth) {
        die("Unknown method: $meth");
    }
    return $self->_couch_handle_new(\%Couchbase::Couch::Handle::RawIterator::);
}

# Gets a design document
sub couch_design_get {
    my ($self,$path) = @_;
    my $handle = $self->_couch_handle_new(
        \%Couchbase::Couch::Handle::Slurpee::);
    my $design = $handle->slurp_jsonized(COUCH_METHOD_GET, "_design/" . $path, "");
    bless $design, 'Couchbase::Couch::Design';
}

# saves a design document
sub couch_design_put {
    my ($self,$design,$path) = @_;
    if (ref $design) {
        $path = $design->{_id};
        $design = encode_json($design);
    }
    my $handle = $self->_couch_handle_new(\%Couchbase::Couch::Handle::Slurpee::);
    return $handle->slurp_jsonized(COUCH_METHOD_PUT, $path, $design);
}

# slurp an entire resultset of views
sub couch_view_slurp {
    my ($self,$viewpath,%options) = @_;
    my $handle = $self->_couch_handle_new(
        \%Couchbase::Couch::Handle::Slurpee::);
    $handle->slurp(COUCH_METHOD_GET, $viewpath, "");
    
}

sub couch_view_iterator {
    my ($self,$viewpath,%options) = @_;
    
    my $handle = $self->_couch_handle_new(
        \%Couchbase::Couch::Handle::ViewIterator::);
    
    $handle->_perl_initialize();
    $handle->prepare(COUCH_METHOD_GET, $viewpath, "");
    return $handle;
}

0xf00d