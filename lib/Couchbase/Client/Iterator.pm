package Couchbase::Client::Iterator;
use strict;
use warnings;

# This is a dummy package. Couchbase::Client should be loaded beforehand.
# The guts of this package are entirely implemented in XS
# This module exists mainly for documentation.

1;

__END__

=head1 NAME

Couchbase::Client::Iterator - Iterator for Couchbase GET requests


=head1 SYNOPSIS

    my @keys = map { "A_Key_$_" } (0..1000);
    
    my $iterator = $cbo->get_iterator(\@keys);
    
    # Might want to check for error:
    if ($iterator->error) {
        die "Couldn't create iterator: " . $iterator->error->errstr();
    }
    
    while (my ($key,$ret) = $iterator->next) {
        printf("I Got value %s for key %s\n", $ret->value, $key);
    }
    
=head2 DESCRIPTION

This package provides the iterator object, allowing a by-key iteration for
multi-get requests.

This increases efficiency on the server-side by reducing packet size, while also
reducing memory usage on the client side (so all responses do not need to be
buffered before they are read).

In particular, if you are fetching a large number of keys (many of which may
not exist), then you save a significant amount of memory involved in compiling
the resultset.

Use of this iterator and its implementation was designed as a model for the more
complex C<Couchbase::Couch> iterator interface.

=head3 $cbo->get_iterator(@keys)

This creates a new iterator. See C<get_multi> in L<Couchbbase::Client> for the
arguments to this function.

Instead of using a normal C<get_multi>, it returns an iterator object which can
be iterated over until all keys are exhausted.

This function always returns a C<Couchbase::Client::Iterator> object.

If an error ocurred during the initial creation, it will be accessible via the
C<error> method.

=head3 $iter->next

When called in list context, returns a pair of C<($key,$return)> pairs, where
C<$key> is one of the keys requested, and C<$return> is a L<Couchbase::Client::Return>
object.

When called in scalar context, it makes a best effort to return the number of
items remaining to be fetched. This is probably not very useful, so don't call
it in scalar context.

When there are no more items to fetch, a false value is returned.

=head3 $iter->error

Returns a L<Couchbase::Client::Return> object if any error has ocurred while
creating the iterator

=head3 $iter->remaining

Returns the amount of items remaining to be fetched

=head2 NOTES AND CAVEATS

Because the client uses a single socket for each server, mixing an iterator
with other request types will at best reduce its effectiveness (all data will
need to be buffered) and break things at worse. So don't do something like:

    while (my ($k,$v) = $iterator->next) {
        $cbo->store($k, "new_v");
    }

If you need such functionality, you should create a second Couchbase::Client
object (thereby creating a second set of streams).

=head1 SEE ALSO

L<Couchbase::Client>