package Couchbase::Couch::Handle;
use strict;
use warnings;
use Couchbase::Client::IDXConst;
use Carp qw(cluck);
use Data::Dumper;

BEGIN {
    require XSLoader;
    XSLoader::load('Couchbase::Client', 0.19);
}

sub _perl_initialize {
    my $self = shift;
    $self->info->_priv([]);
    $self->info->[COUCHIDX_CALLBACK_DATA] = \&default_data_callback;
    $self->info->[COUCHIDX_CALLBACK_COMPLETE] = \&default_complete_callback;
    return $self;
}

sub path { shift->info->path }

sub default_data_callback {
    cluck "Got unhandled data callback";
    print Dumper($_[1]);
}
sub default_complete_callback {
    print Dumper($_[1]);
    cluck "Got unhandled completion callback..";
}

package Couchbase::Couch::Handle::ViewIterator;
use strict;
use warnings;
use Constant::Generate [qw(ITERBUF JSNDEC)], -prefix => 'FLD_';
use Couchbase::Client::IDXConst;
use JSON::SL;
use Couchbase::Couch::Handle;
use Couchbase::Couch::ViewRow;

use base qw(Couchbase::Couch::Handle);

# This is called when new data arrives,
# in C-speak, this is called from call_to_perl
sub _cb_data {
    my ($self,$info,$bytes) = @_;
    return unless defined $bytes;
    my $check_again;
    my $sl = $info->_priv->[FLD_JSNDEC];
    my $buf = $info->_priv->[FLD_ITERBUF];
    my @results = $sl->feed($bytes);
    my $rescount = scalar @results;
    
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
    
}

sub count {
    my $self = shift;
    $self->info->_extract_item_count($self->info->_priv->[FLD_JSNDEC]->root);
}

sub next {
    my $self = shift;
    my $rows = $self->info->_priv->[FLD_ITERBUF];
    if (@$rows) {
        return shift @$rows;
    }
    my $rv = $self->_iter_step;
    if ($rv) {
        die "Iteration stopped but got nothing in buffer" unless @$rows;
        return shift @$rows;
    }
    #complex case. Iteration stopped. Collect errors and metadata..
    $self->count; #sets count, if it doesn't exist yet.
    $self->info->_extract_row_errors($self->info->_priv->[FLD_JSNDEC]->root);
    return shift @$rows;
}

sub remaining_json {
    my $self = shift;
    if ($self->info->_priv->[FLD_JSNDEC]) {
        return $self->info->_priv->[FLD_JSNDEC]->root;
    }
}

sub _perl_initialize {
    my $self = shift;
    my %options = @_;
    $self->SUPER::_perl_initialize(%options);
    my $priv = $self->info->_priv;
    $priv->[FLD_JSNDEC] = JSON::SL->new();
    $priv->[FLD_ITERBUF] = [];
    $self->info->[COUCHIDX_CALLBACK_DATA] = \&_cb_data;
    $self->info->[COUCHIDX_CALLBACK_COMPLETE] = \&_cb_complete;
    $priv->[FLD_JSNDEC]->set_jsonpointer(["/rows/^"]);
    return $self;
}

package Couchbase::Couch::Handle::Slurpee;
use strict;
use warnings;
use JSON::XS;
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
        $info->[RETIDX_VALUE] = JSON::XS::decode_json($info->[RETIDX_VALUE]);
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
