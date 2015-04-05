package Couchbase::HTTPDocument;
use strict;
use warnings;
use Couchbase::Constants;
use Couchbase::_GlueConstants;
use base (qw(Couchbase::Document));
use JSON;

use Class::XSAccessor::Array accessors => {
    http_code => HTIDX_STATUS,
    http_status => HTIDX_STATUS,
    headers => HTIDX_HEADERS,
    path => RETIDX_KEY
};

sub is_ok {
    my $self = shift;
    my $ret = $self->SUPER::is_ok();
    if (!$ret) {
        return $ret;
    }
    return $self->http_code =~ m/^2/;
}

sub errstr {
    my $self = shift;
    if ($self->is_ok) {
        return '';
    }

    my $ret = $self->SUPER::errstr() || '';
    $ret .= " HTTP code: " . ($self->http_code || "(not received)");
    return $ret;
}

1;
