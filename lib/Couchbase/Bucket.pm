package Couchbase::Bucket;
use strict;
use warnings;
use Couchbase::DocIterator;
use Couchbase::Client::Errors;
use Couchbase::Client::IDXConst;
use Couchbase::Document;
use Couchbase::Couch::Handle;
use Couchbase::Couch::HandleInfo;
use Couchbase::Couch::Design;
use JSON;
use JSON::SL;
use Data::Dumper;
use URI;

my $have_storable = eval "use Storable; 1;";
my $have_zlib = eval "use Compress::Zlib; 1;";

use Array::Assign;

# Get the CouchDB (2.0) API
use Couchbase::Couch::Base;
use base qw(Couchbase::Couch::Base);

#this function converts hash options for compression and serialization
#to something suitable for construct()

sub _make_conversion_settings {
    my ($arglist,$options) = @_;
    my $flags = 0;


    $arglist->[CTORIDX_MYFLAGS] ||= 0;

    if($options->{dereference_scalar_ref}) {
        $arglist->[CTORIDX_MYFLAGS] |= fDEREF_RVPV;
    }

    if(exists $options->{deconversion}) {
        if(! delete $options->{deconversion}) {
            return;
        }
    } else {
        $flags |= fDECONVERT;
    }

    if(exists $options->{compress_threshold}) {
        my $compress_threshold = delete $options->{compress_threshold};
        $compress_threshold =
            (!$compress_threshold || $compress_threshold < 0)
            ? 0 : $compress_threshold;
        $arglist->[CTORIDX_COMP_THRESHOLD] = $compress_threshold;
        if($compress_threshold) {
            $flags |= fUSE_COMPRESSION;
        }
    }

    my $meth_comp;
    if(exists $options->{compress_methods}) {
        $meth_comp = delete $options->{compress_methods};
    } elsif($have_zlib) {
        $meth_comp = [ sub { ${$_[1]} = Compress::Zlib::memGzip(${$_[0]}) },
                      sub { ${$_[1]} = Compress::Zlib::memGunzip(${$_[0]}) }]
    }

    if(defined $meth_comp) {
        $arglist->[CTORIDX_COMP_METHODS] = $meth_comp;
    }

    my $meth_serialize = 0;
    if(exists $options->{serialize_methods}) {
        $meth_serialize = delete $options->{serialize_methods};
    }

    if($meth_serialize == 0 && $have_storable) {
        $meth_serialize = [ \&Storable::freeze, \&Storable::thaw ];
    }

    if($meth_serialize) {
        $flags |= fUSE_STORABLE;
        $arglist->[CTORIDX_SERIALIZE_METHODS] = $meth_serialize;
    }

    $arglist->[CTORIDX_MYFLAGS] |= $flags;
}

sub _MkCtorIDX {
    my $opts = shift;

    my @arglist;
    my $connstr = delete $opts->{connstr} or die "Must have server";
    arry_assign_i(@arglist,
        CTORIDX_CONNSTR, $connstr,
        CTORIDX_PASSWORD, delete $opts->{password});

    _make_conversion_settings(\@arglist, $opts);
    $arglist[CTORIDX_NO_CONNECT] = delete $opts->{no_init_connect};


    if(keys %$opts) {
        warn sprintf("Unused keys (%s) in constructor",
                     join(", ", keys %$opts));
    }
    return \@arglist;
}

sub new {
    my ($pkg, $connstr, $opts) = @_;
    $opts ||= {};
    my $privopts = { %$opts, connstr => $connstr };
    my $arglist = _MkCtorIDX($privopts);
    my $self = $pkg->construct($arglist);
    return $self;
}


# Returns a 'raw' request handle
sub _htraw {
    my $self = $_[0];
    return $self->_new_viewhandle(\%Couchbase::Couch::Handle::RawIterator::);
}

# Gets a design document
sub design_get {
    my ($self,$path) = @_;
    my $handle = $self->_new_viewhandle(\%Couchbase::Couch::Handle::Slurpee::);
    my $design = $handle->slurp_jsonized("GET", "_design/" . $path, "");
    bless $design, 'Couchbase::Couch::Design';
}

# saves a design document
sub design_put {
    my ($self,$design,$path) = @_;
    if (ref $design) {
        $path = $design->{_id};
        $design = encode_json($design);
    }
    my $handle = $self->_new_viewhandle(\%Couchbase::Couch::Handle::Slurpee::);
    return $handle->slurp_jsonized("PUT", $path, $design);
}

sub _process_viewpath_common {
    my ($orig,%options) = @_;
    my %qparams;

    if (delete $options{ForUpdate}) {
        $qparams{include_docs} = "true";
    }
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
    my $handle = $self->_new_viewhandle(\%Couchbase::Couch::Handle::Slurpee::);

    if (delete $options{ForUpdate}) {
        $viewpath .= "?include_docs=true";
    }
    $viewpath = _process_viewpath_common($viewpath,%options);
    $handle->slurp("GET", $viewpath, "");
}

sub view_iterator {
    my ($self,$viewpath,%options) = @_;
    my $handle;

    $viewpath = _process_viewpath_common($viewpath, %options);
    $handle = $self->_new_viewhandle(\%Couchbase::Couch::Handle::ViewIterator::);
    $handle->_perl_initialize();
    $handle->prepare("GET", $viewpath, "");
    return $handle;
}

1;
