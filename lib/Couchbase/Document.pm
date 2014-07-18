package Couchbase::Document;
use strict;
use warnings;

use Couchbase::Client::IDXConst;

use Class::XSAccessor::Array {
    accessors => {
        id => RETIDX_KEY,
        expiry => RETIDX_EXP,
        cas => RETIDX_CAS,
        value => RETIDX_VALUE,
        errnum => RETIDX_ERRNUM,
        errstr => RETIDX_ERRSTR
    }
};

sub is_ok { $_[0]->[RETIDX_ERRNUM] == COUCHBASE_SUCCESS }

sub new {
    my ($pkg, $id, $doc) = @_;
    my $rv = bless [], $pkg;
    $rv->id($id);
    $rv->value($doc);
    return $rv;
}

1;
