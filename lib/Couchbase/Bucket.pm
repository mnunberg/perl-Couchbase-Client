package Couchbase::Bucket;
use strict;
use warnings;

use Couchbase;
use Couchbase::Client::IDXConst;
use Couchbase::Document;
use Couchbase::Settings;
use Couchbase::OpContext;
use JSON;
use JSON::SL;
use Data::Dumper;
use URI;
use Storable;

use Couchbase::View::Handle;
use Couchbase::View::HandleInfo;

our $_JSON = JSON->new()->allow_nonref;
sub _js_encode { $_JSON->encode($_[0]) }
sub _js_decode { $_JSON->decode($_[0]) }

sub new {
    my ($pkg, $connstr, $opts) = @_;
    $opts ||= {};
    die("Must have connection string") unless $connstr;

    my %options = (connstr => $connstr);

    if ($opts->{password}) {
        $options{password} = $opts->{password};
    }
    my $self = $pkg->construct(\%options);
    $self->connect();
    $self->_set_converters(CONVERTERS_JSON, \&_js_encode, \&_js_decode);
    $self->_set_converters(CONVERTERS_STORABLE, \&Storable::freeze, \&Storable::thaw);
    return $self;
}

sub settings {
    my $self = shift;
    tie my %h, 'Couchbase::Settings', $self;
    return \%h;
}

# Returns a 'raw' request handle
sub _htraw {
    my $self = $_[0];
    return $self->_new_viewhandle(\%Couchbase::View::Handle::RawIterator::);
}

# Gets a design document
sub design_get {
    my ($self,$path) = @_;
    my $handle = $self->_new_viewhandle(\%Couchbase::View::Handle::Slurpee::);
    my $design = $handle->slurp_jsonized("GET", "_design/" . $path, "");
    bless $design, 'Couchbase::View::Design';
}

# saves a design document
sub design_put {
    my ($self,$design,$path) = @_;
    if (ref $design) {
        $path = $design->{_id};
        $design = encode_json($design);
    }
    my $handle = $self->_new_viewhandle(\%Couchbase::View::Handle::Slurpee::);
    return $handle->slurp_jsonized("PUT", $path, $design);
}

sub _process_viewpath_common {
    my ($orig,%options) = @_;
    my %qparams;
    if (%options) {
        # TODO: pop any other known parameters?
        %qparams = (%qparams,%options);
    }

    if (ref $orig ne 'ARRAY') {
        if (!$orig) {
            die("Path cannot be empty");
        }
        $orig = [($orig =~ m,([^/]+)/(.*),)]
    }

    unless ($orig->[0] && $orig->[1]) {
        die("Path cannot be empty");
    }

    # Assume this is an array of [ design, view ]
    $orig = sprintf("_design/%s/_view/%s", @$orig);

    if (%qparams) {
        $orig = URI->new($orig);
        $orig->query_form(\%qparams);
    }

    return $orig . "";
}

# slurp an entire resultset of views
sub view_slurp {
    my ($self,$viewpath,%options) = @_;
    my $handle = $self->_new_viewhandle(\%Couchbase::View::Handle::Slurpee::);
    $viewpath = _process_viewpath_common($viewpath,%options);
    return $handle->slurp("GET", $viewpath, "");
}

sub view_iterator {
    my ($self,$viewpath,%options) = @_;
    my $handle;

    $viewpath = _process_viewpath_common($viewpath, %options);
    $handle = $self->_new_viewhandle(\%Couchbase::View::Handle::ViewIterator::);
    $handle->_perl_initialize();
    $handle->prepare("GET", $viewpath, "");
    return $handle;
}

1;
