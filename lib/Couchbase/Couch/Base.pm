# This module forms the CouchDB parts of
# Couchbase::Client's API

package Couchbase::Couch::Base;
use strict;
use warnings;
use Couchbase::Couch::Handle;
use Couchbase::Client::IDXConst;

# The following methods are defined in Client.xs
# and alias to the memcached set() method, with
# special behavior for converting objects into
# JSON


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

=head2 SEE ALSO

L<Couchbase::Couch::Handle> - contains documentation for
C<Couchbase::Couch::ViewIterator>

L<Couchbase::Couch::HandleInfo> - Documents the L<Couchbase::Client::Return>-like
object for fetching view row metadata

L<Couchbase::Couch::ViewRow> - Documents the row objects returned by the
iterator.
