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
use base qw(Couchbase::Couch::Handle);

sub _cb_data {
    my ($self,$info,$bytes) = @_;
    return unless defined $bytes;
    my $check_again;
    my $sl = $info->_priv->[FLD_JSNDEC];
    my $buf = $info->_priv->[FLD_ITERBUF];
    my @results = $sl->feed($bytes);
    my $rescount = scalar @results;
    
    foreach (@results) {
        push @$buf, $_->{Value};
    }
    
    if ($rescount) {
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
    $self->SUPER::_perl_initialize();
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