# This isn't used by anything (yet), but might be handy for attachments -
# iterates through the response, but does not parse it.
package Couchbase::View::Handle::RawIterator;
use strict;
use warnings;
use Couchbase::_GlueConstants;
use base qw(Couchbase::View::Handle);

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
