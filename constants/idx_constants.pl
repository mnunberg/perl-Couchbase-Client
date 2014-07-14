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
    CTORIDX_CONNSTR
    CTORIDX_PASSWORD
    CTORIDX_STOREFLAGS
    CTORIDX_MYFLAGS

    CTORIDX_COMP_THRESHOLD
    CTORIDX_COMP_METHODS

    CTORIDX_SERIALIZE_METHODS

    CTORIDX_TIMEOUT
    CTORIDX_NO_CONNECT

    CTORIDX_JSON_ENCODE_METHOD
    CTORIDX_JSON_VERIFY_METHOD

    RETIDX_VALUE
    RETIDX_ERRSTR
    RETIDX_CAS
    RETIDX_ERRNUM

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

my @http_methods = qw(GET POST PUT DELETE);

constant("LCB_HTTP_METHOD_$_",
         name => "COUCH_METHOD_$_") for (@http_methods);

write_output($ARGV[0]);
