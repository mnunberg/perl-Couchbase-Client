use PLCB_ConfUtil;

BEGIN {
    PLCB_ConfUtil::env_from_tmpflags();
}

use ExtUtils::H2PM;
module "Couchbase::Client::IDXConst";
use_export;


include "sys/types.h";
include "perl-couchbase.h";

my @const_bases = qw(
    RETIDX_VALUE
    RETIDX_CAS
    RETIDX_ERRNUM
    RETIDX_KEY
    RETIDX_EXP

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
);

constant("PLCB_$_", name => $_) for (@const_bases);

my @ctor_flags = qw(
    USE_COMPAT_FLAGS
    USE_COMPRESSION
    USE_STORABLE
    USE_CONVERT_UTF8
    NO_CONNECT
    DECONVERT
    DEREF_RVPV
);

constant("PLCBf_$_", name => "f$_") for (@ctor_flags);
write_output($ARGV[0]);
