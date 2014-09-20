package Couchbase::Document;
use strict;
use warnings;

use Couchbase::Client::IDXConst;
use Couchbase::Client::Errors;

use Class::XSAccessor::Array {
    accessors => {
        id => RETIDX_KEY,
        expiry => RETIDX_EXP,
        cas => RETIDX_CAS,
        value => RETIDX_VALUE,
        errnum => RETIDX_ERRNUM,
    }
};

sub is_ok { $_[0]->[RETIDX_ERRNUM] == COUCHBASE_SUCCESS }

sub new {
    my ($pkg, $id, $doc, $options) = @_;
    my $rv = bless [], $pkg;
    $rv->id($id);
    $rv->value($doc);

    if ($options) {
        while (my ($k,$v) = each %$options) {
            no strict 'refs';
            $rv->$k ($v);
        }
    }

    return $rv;
}

1;
