package Couchbase::Document;
use strict;
use warnings;

use Couchbase::_GlueConstants;
use Couchbase::Constants;
use Couchbase;
use base qw(Exporter);

our @EXPORT = (qw(COUCHBASE_FMT_JSON COUCHBASE_FMT_UTF8 COUCHBASE_FMT_RAW COUCHBASE_FMT_STORABLE));

use Class::XSAccessor::Array {
    accessors => {
        id => RETIDX_KEY,
        expiry => RETIDX_EXP,
        cas => RETIDX_CAS,
        value => RETIDX_VALUE,
        errnum => RETIDX_ERRNUM
    }
};

sub is_ok { $_[0]->[RETIDX_ERRNUM] == COUCHBASE_SUCCESS }
sub is_not_found { $_[0]->[RETIDX_ERRNUM] == COUCHBASE_KEY_ENOENT }
sub is_cas_mismatch { $_[0]->[RETIDX_ERRNUM] == COUCHBASE_KEY_EEXISTS }

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

sub errstr {
    my $self = shift;
    my $rc = $self->errnum;
    my $s = $Couchbase::ErrorMap[$rc];
    if (! $s) {
        $s = $Couchbase::ErrorMap[$rc] = Couchbase::strerror($rc);
    }
    return $s;
}


our %FMT_STR2NUM = (
    utf8 => COUCHBASE_FMT_UTF8,
    raw => COUCHBASE_FMT_RAW,
    storable => COUCHBASE_FMT_STORABLE,
    json => COUCHBASE_FMT_JSON
);

sub format {
    if (scalar @_ == 1) {
        return $_[0]->[RETIDX_FMTSPEC]
    }
    my $fmtspec = $_[1];

    if ($fmtspec !~ /^\d+$/) {
        my $numfmt = $FMT_STR2NUM{$fmtspec};
        if (! defined($numfmt)) {
            die("Unrecognized format code " . $fmtspec);
        }
        $fmtspec = $numfmt;
    }
    $_[0]->[RETIDX_FMTSPEC] = $fmtspec;
}

1;
