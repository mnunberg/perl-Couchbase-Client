# This handle simply 'slurps' data. It has three modes
# 1) Raw - Just slurp the stream of bytes and return it
# 2) JSONized - Slurp the stream and convert it into JSON, but don't do anything else
# 3) Resultset - Slurp the stream, and treat it as a resultset of JSON view rows
package Couchbase::View::Handle::Slurpee;
use strict;
use warnings;
use JSON;
use Couchbase::_GlueConstants;
use base qw(Couchbase::View::Handle);

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
    if ($self->info && ref $self->info->rows eq 'ARRAY') {
        bless $_, 'Couchbase::View::Row' for @{$self->info->rows};
    }

    return $self->info;
}

1;
