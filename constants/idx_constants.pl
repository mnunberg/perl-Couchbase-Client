use PLCB_ConfUtil;

BEGIN {
    PLCB_ConfUtil::env_from_tmpflags();
}

use ExtUtils::H2PM;
module "Couchbase::_GlueConstants";
use_export;


include "sys/types.h";
include "perl-couchbase.h";
include "libcouchbase/vbucket.h";

my @const_bases = qw(
    RETIDX_VALUE
    RETIDX_PARENT
    RETIDX_CAS
    RETIDX_ERRNUM
    RETIDX_KEY
    RETIDX_EXP
    RETIDX_FMTSPEC

    COUCHIDX_HTTP
    COUCHIDX_CALLBACK_DATA
    COUCHIDX_CALLBACK_COMPLETE
    COUCHIDX_PATH
    COUCHIDX_UDATA
    COUCHIDX_CBO
    COUCHIDX_ERREXTRA
    COUCHIDX_ROWCOUNT

    ROWIDX_CBO
    ROWIDX_DOCID
    ROWIDX_REV

    CONVERTERS_JSON
    CONVERTERS_CUSTOM
    CONVERTERS_STORABLE

    SETTING_INT
    SETTING_UINT
    SETTING_U32
    SETTING_SIZE
    SETTING_TIMEOUT
    SETTING_STRING

    OPCTXIDX_FLAGS
    OPCTXIDX_REMAINING
    OPCTXIDX_QUEUE
    OPCTXIDX_CBO

    OPCTXf_IMPLICIT
    OPCTXf_WAITONE
);

constant("PLCB_$_", name => $_) for (@const_bases);


# Also generate the ones for flags:
my @fmt_bases = (qw(RAW JSON UTF8 STORABLE));
constant("PLCB_CF_$_", name => "COUCHBASE_FMT_$_") for (@fmt_bases);
constant("LCBVB_SVCTYPE_$_", name => "SVCTYPE_$_") for (qw(DATA VIEWS MGMT));
constant("LCBVB_SVCMODE_$_", name => "SVCMODE_$_") for (qw(PLAIN SSL));

write_output($ARGV[0]);
