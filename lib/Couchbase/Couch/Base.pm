# This module forms the CouchDB parts of
# Couchbase::Client's API

package Couchbase::Couch::Base;
use strict;
use warnings;
use Couchbase::Couch::Handle;
use Couchbase::Couch::HandleInfo;
use Couchbase::Couch::Design;
use Couchbase::Client::IDXConst;
use JSON;
use JSON::SL;
use Data::Dumper;
use URI;


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

# gets a couch document. Quite simple..
sub couch_doc_get {
    my $self = shift;
    my $ret = $self->get(@_);
    if ($ret->value) {
        $ret->[RETIDX_VALUE] = decode_json($ret->[RETIDX_VALUE]);
    }
    return $ret;
}

{
    no warnings 'once';
    *couch_doc_store = *Couchbase::Client::couch_set;
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

    if (ref $orig eq 'ARRAY') {
        # Assume this is an array of [ design, view ]
        $orig = sprintf("_design/%s/_view/%s", @$orig);
    }


    if (%qparams) {
        $orig = URI->new($orig);
        $orig->query_form(\%qparams);
    }

    return $orig . "";
}

# slurp an entire resultset of views
sub couch_view_slurp {
    my ($self,$viewpath,%options) = @_;
    my $handle = $self->_couch_handle_new(
        \%Couchbase::Couch::Handle::Slurpee::);
    if (delete $options{ForUpdate}) {
        $viewpath .= "?include_docs=true";
    }
    $viewpath = _process_viewpath_common($viewpath,%options);
    $handle->slurp(COUCH_METHOD_GET, $viewpath, "");

}

sub couch_view_iterator {
    my ($self,$viewpath,%options) = @_;

    $viewpath = _process_viewpath_common($viewpath, %options);

    my $handle = $self->_couch_handle_new(
        \%Couchbase::Couch::Handle::ViewIterator::);

    $handle->_perl_initialize();
    $handle->prepare(COUCH_METHOD_GET, $viewpath, "");
    return $handle;
}

0xf00d

__END__

=head1 NAME

Couchbase::Couch::Base - API For Couch Operations

=head1 SYNOPSIS

    NYI

=head1 DESCRIPTION

All documentation here pertains to L<Couchbase::Client> which is the client object
representing a couchbase connection. This manual page documents the I<Couch> (i.e.
I<CouchDB>) interface, with some differences

Whereas the 'normal' interface in L<Couchbase::Client> describes the mainly C<memcached>
API, this describes dealing with views and design documents.

B<NOTE: This is a work in progress and the interface is subject to change! You
have been warned>

All return values, unless otherwise specified, conform to the
L<Couchbase::Couch::HandleInfo> which is itself a subclass of
L<Couchbase::Client::Return>.

This means the error codes and metadata are found in the returned object, and the
actual data may be accessed by using the C<data> method.

=head2 Dealing with design documents

Design documents are returned as L<Couchbase::Couch::Design> objects, a subclass
of L<Couchbase::Couch::HandleInfo>

Design documents encapsulate one or more views. They are simple JSON objects
which this module converts to perl hashes.

=head3 couch_design_get($name)

Get the design document with the name C<$name>. C<$name> is not a path, but a
simple name. To get a 'development' mode design, simply use C<"_dev_$name">.

=head3 couch_design_put($hash_or_json,$path)

Save the design document under the specified path. The first argument may either
be an encoded JSON string, or a hash, which this module shall encode for you.

=head2 Views

=head3 couch_view_slurp($path,%options)

Get all results from a view. C<$path> may be a string path (i.e. the
path component of the URI), or an arrayref of C<[$design, $view]>.

C<%options> may be a hash of options. Recognized
options are directives to this module for behavior, while unrecognized options
are passed as-is as query parameters to the view engine.

There are no recognized options for C<slurp>-mode view execution.

This method returns a L<Couchbase::Couch::HandleInfo> object. The actual rows/results
may be accessed by calling the C<rows> method on the returned object.


=head3 couch_view_iterator($path,%options)

Initialize an iterator object (specifically, a L<Couchbase::Couch::Handle>)
for incremental processing of large result sets.

The iterator works as so:

    my $iter = $cbo->couch_view_iterator("_design/blog/_view/recent_post");
    while (my $row = $iter->next) {
        # do something with $row
    }

Where C<$row> is a L<Couchbase::Couch::ViewRow> object (the resultant
hash is blessed as-is into this package).

The C<$path> and C<%options> parameters follow the same semantics as in
L<couch_view_slurp> with the following I<recognized> options:

=over

=item C<ForUpdate>

Execute the view query in 'extended' mode. This means to perform some extra work
in order to make in-place updates easier. Specifically, this means allowing
the shorthand C<< $row->save >> idiom, as well as including the entire document
within each row.

=back

=head2 Documents

These methods really just call their memcached equivalents with some extra
behavior specific to ensuring values are converted to and from JSON

=head3 couch_doc_get($key, ...)

Follows the same semantics as L<Couchbase::Client>'s C<get>

=head3 couch_doc_store($key,$value,...)

Follows the same semantics as L<Couchbase::Client>'s C<set>
