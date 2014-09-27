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
        _cas => RETIDX_CAS,
        value => RETIDX_VALUE,
        errnum => RETIDX_ERRNUM
    }
};

sub is_ok { $_[0]->[RETIDX_ERRNUM] == COUCHBASE_SUCCESS }
sub is_not_found { $_[0]->[RETIDX_ERRNUM] == COUCHBASE_KEY_ENOENT }
sub is_cas_mismatch { $_[0]->[RETIDX_ERRNUM] == COUCHBASE_KEY_EEXISTS }
sub is_already_exists { $_[0]->[RETIDX_ERRNUM] == COUCHBASE_KEY_EEXISTS }
sub new {
    my ($pkg, $id, $doc, $options) = @_;
    if (ref $id && $id->isa($pkg)) {
        return $id->copy();
    }

    my $rv = bless [], $pkg;
    $rv->id($id);
    $rv->value($doc);
    $rv->format(COUCHBASE_FMT_JSON);

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

sub copy {
    my $self = shift;
    bless my $cp = [@$self], 'Couchbase::Document';

    $cp->_cas(0);
    $cp->[RETIDX_PARENT] = undef;
    return $cp;
}

our %FMT_STR2NUM = (
    utf8 => COUCHBASE_FMT_UTF8,
    raw => COUCHBASE_FMT_RAW,
    storable => COUCHBASE_FMT_STORABLE,
    json => COUCHBASE_FMT_JSON
);

our %FMT_NUM2STR = reverse(%FMT_STR2NUM);

sub format {
    my ($self, $fmtspec) = @_;
    if (scalar @_ == 1) {
        my ($fmt_s, $fmt_i) = (undef, $self->[RETIDX_FMTSPEC]);
        if (wantarray) {
            $fmt_s = $FMT_NUM2STR{$fmt_i} || "UNKNOWN";
            return ($fmt_s, $fmt_i);
        }
        return $fmt_i;
    }

    if ($fmtspec !~ /^\d+$/) {
        my $numfmt = $FMT_STR2NUM{$fmtspec};
        if (! defined($numfmt)) {
            die("Unrecognized format code " . $fmtspec);
        }
        $fmtspec = $numfmt;
    }
    $_[0]->[RETIDX_FMTSPEC] = $fmtspec;
}

# This doesn't really mean anything special, but is akin to what's used in Python:
sub as_hash {
    my $self = shift;
    my ($fmt_s, $fmt_i) = $self->format;
    my %h = (
        id => $self->id,
        value => $self->value,
        status => $self->errnum,
        'status (string)' => $self->errstr,
        format => sprintf("0x%X (%s)", $fmt_i, $fmt_s),
        expiry => $self->expiry,
        CAS => sprintf("0x%X", $self->_cas)
    );
    return \%h;
}

package Couchbase::StatsResult;
use strict;
use warnings;
use base qw(Couchbase::Document);


package Couchbase::ObserveResult;
use strict;
use warnings;
use base qw(Couchbase::Document);

1;
