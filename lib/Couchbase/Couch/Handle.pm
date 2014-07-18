package Couchbase::Couch::Handle;
##
# This is mainly an (abstract) base class for all handle objects.
use strict;
use warnings;
use Couchbase;
use Couchbase::Client::IDXConst;
use Carp qw(cluck);
use Data::Dumper;
use base qw(Couchbase::View);

# This does some boilerplate initialization, ensuring that our private
# fields are initialized. Subclasses usually override this method and end up
# calling this via SUPER
sub _perl_initialize {
    my $self = shift;
    $self->info->_priv([]);

    # These two statements declare the callbacks.
    # The CALLBACK_DATA and CALLBACK_COMPLETE correspond to the handlers which
    # will be invoked by libcouchbase for the respective events.
    # These callbacks should warn.

    $self->info->[COUCHIDX_CALLBACK_DATA] = \&default_data_callback;
    $self->info->[COUCHIDX_CALLBACK_COMPLETE] = \&default_complete_callback;
    return $self;
}

# Convenience function
sub path { shift->info->path }

sub default_data_callback {
    cluck "Got unhandled data callback";
    print Dumper($_[1]);
}

sub default_complete_callback {
    print Dumper($_[1]);
    cluck "Got unhandled completion callback..";
}

# This is the primary class for an iterator receiving a stream of bytes,
# and incrementally returning a JSON object (specifically, a view row) as its
# atomic unit.
package Couchbase::Couch::Handle::ViewIterator;
use strict;
use warnings;
use Constant::Generate [qw(ITERBUF JSNDEC JSNROOT)], -prefix => 'FLD_';
use Couchbase::Client::IDXConst;
use JSON::SL;
use Couchbase::Couch::Handle;
use Couchbase::Couch::ViewRow;
use Data::Dumper;

use base qw(Couchbase::Couch::Handle);


sub _perl_initialize {
    my $self = shift;
    my %options = @_;
    $self->SUPER::_perl_initialize(%options);

    my $priv = $self->info->_priv;

    # Establish our JSON::SL object.
    $priv->[FLD_JSNDEC] = JSON::SL->new();

    $priv->[FLD_JSNDEC]->root_callback(sub {
        if ($_[0]) {
            $priv->[FLD_JSNROOT] = $_[0]
        }
    });

    # Set the path for objects we wish to receive. Anything under "rows": [ ..]
    # is a result for the user
    $priv->[FLD_JSNDEC]->set_jsonpointer(["/rows/^"]);

    # This array reference will serve as a FIFO queue. A user will receive
    # objects from the head, while JSON::SL will write parsed JSON objects
    # to its tail.
    $priv->[FLD_ITERBUF] = [];

    # Set up our callbacks..
    $self->info->[COUCHIDX_CALLBACK_DATA] = \&_cb_data;
    $self->info->[COUCHIDX_CALLBACK_COMPLETE] = \&_cb_complete;

    return $self;
}


# This is called when new data arrives,
# in C-speak, this is called from call_to_perl
sub _cb_data {
    # the first argument is the handle, second is a special informational
    # structure (which also contains our private data) and the third is
    # a bunch of bytes
    my ($self,$info,$bytes) = @_;
    return unless defined $bytes;

    my $sl = $info->_priv->[FLD_JSNDEC];
    my $buf = $info->_priv->[FLD_ITERBUF];

    # pass some more data into JSON::SL
    my @results = $sl->feed($bytes);

    # check to see what our result count was for this stream of bytes. If we have
    # received at least one extra object, then we can be assured the user has
    # enough data, and therefore we can signal to the C code to stop the event
    # loop (or decrement the wait count)
    my $rescount = scalar @results;

    # This converts results (as raw JSON::SL results) into more sugary
    # objects for Couch
    foreach (@results) {
        my $o = $_->{Value};
        bless $o, "Couchbase::Couch::ViewRow";
        $o->_cbo($self->info->[COUCHIDX_CBO]);
        push @$buf, $o;
    }

    if ($rescount) {
        # if we have enough data, it is time to signal to the C code that
        # the internal event loop should be unreferenced (i.e. we no longer
        # need to wait for this operation to complete)
        $self->_iter_pause;
    }
}

sub _cb_complete {
    # hrrm.. not sure what to put here?
}

# convenience method. Returns the 'total_rows' field.
sub count {
    my $self = shift;
    $self->info->_extract_item_count($self->info->_priv->[FLD_JSNROOT]);
    return $self->info->count;
}

# User level entry point to the iterator.
sub next {
    my $self = shift;
    my $rows = $self->info->_priv->[FLD_ITERBUF];
    my $is_wantarray = wantarray();

    my $return_stuff = sub {
        if ($is_wantarray) {
            my @ret = @$rows;
            @$rows = ();
            return @ret;
        }
        return shift @$rows;
    };

    # First we checked if there are remaining items in the row queue. If there are
    # then we don't need to do any network I/O, but simply pop an item and
    # return.
    if (@$rows) {
        return $return_stuff->();
    }

    # so there's nothing in the queue. See if we can get something from the
    # network.
    my $rv = $self->_iter_step;

    # a true return value means we can wait for extra data
    if ($rv) {
        return $return_stuff->();
    }

    # if $rv is false, then we cannot wait for more data (either error, terminated)
    # or some other condition. In this case we finalize the resultset metadata
    $self->info->_extract_row_errors($self->info->_priv->[FLD_JSNROOT]);

    # TODO: does this line actually do anything?
    return $return_stuff->();
}

# convenience method to return any remaining JSON not parsed or extracted.
sub remaining_json {
    my $self = shift;
    return $self->info->_priv->[FLD_JSNROOT];
}

# This handle simply 'slurps' data. It has three modes
# 1) Raw - Just slurp the stream of bytes and return it
# 2) JSONized - Slurp the stream and convert it into JSON, but don't do anything else
# 3) Resultset - Slurp the stream, and treat it as a resultset of JSON view rows
package Couchbase::Couch::Handle::Slurpee;
use strict;
use warnings;
use JSON;
use Couchbase::Client::IDXConst;
use base qw(Couchbase::Couch::Handle);

sub slurp_raw {
    my ($self,@args) = @_;
    $self->SUPER::slurp(@args);
    $self->info;
}

sub slurp_jsonized {
    my ($self,@args) = @_;
    $self->slurp_raw(@args);
    my $info = $self->info;
    if ($info->value) {
        $info->[RETIDX_VALUE] = decode_json($info->[RETIDX_VALUE]);
        $info->_extract_row_errors($info->value);
    }
    return $info;
}

sub slurp {
    my ($self,@args) = @_;
    $self->slurp_raw(@args);
    $self->info->_extract_view_results;
    return $self->info;
}

# This isn't used by anything (yet), but might be handy for attachments -
# iterates through the response, but does not parse it.
package Couchbase::Couch::Handle::RawIterator;
use strict;
use warnings;
use Couchbase::Client::IDXConst;
use base qw(Couchbase::Couch::Handle);

sub _cb_data {
    my ($self,$info,$bytes) = @_;
    if ($bytes) {
        $self->info->[RETIDX_VALUE] .= $bytes;
        $self->_iter_pause();
    }
}

sub _perl_initialize {
    my $self = shift;
    $self->info->[COUCHIDX_CALLBACK_DATA] =\&cb_data;
}

sub next {
    my $self = shift;
    my $ret = delete $self->info->[RETIDX_VALUE];
    if ($ret) {
        return $ret;
    }
    if ($self->_iter_step) {
        return delete $self->info->[RETIDX_VALUE];
    }
    return;
}
1;

__END__

=head1 NAME


Couchbase::Couch::Handle - Class for couch request handles

=head1 DESCRIPTION

This class represents a common inteface for various request handles.
Emphasis will be placed on the iterating view handle, since this is the most common
use case (technical and more 'correct' documentation will follow).

The iterator is simple to use. Simply initialize it (which is done for you
automatically by one of the L<Couchbase::Couch::Base> methods which return this
object) and step through it. When there are no more results through which to
step, the iterator is empty.

Note that iterator objects are fully re-entrant and fully compatible with the
normal L<Couchbase::Client> blocking API. This means that multiple iterators are
allowed, and that you may perform modifications on the items being iterated
upon.

=head2 Couchbase::Couch::Handle::ViewIterator

=head2 next()

Return the next result in the iterator. The returned object is either a false
value (indicating no more results), or a L<Couchbase::Couch::ViewRow> object.

If called in array/list context, a list of rows is returned; the amount of rows
returned is dependent on how much data is currently in the row read buffer.

=head2 stop()

Abort iteration. This means to stop fetching extra data from the network. There
will likely still be extra data available from L</next>

=head2 path()

Returns the path for which this iterator was issued

=head2 count()

Returns the total amount of rows in the result set. This does not mean the amount
of rows which will be returned via the iterator, but rather the server-side count
of the the rows which matched the query parameters

=head2 info()

This returns a L<Couchbase::Couch::HandleInfo> object to obtain metadata about
the view execution. This will usually only return something meaningful after all
rows have been fetched (but you can try!)

=head2 remaining_json()

Return the remaining JSON structure as a read-only hashref. Useful if you think
the iterator is missing something.
