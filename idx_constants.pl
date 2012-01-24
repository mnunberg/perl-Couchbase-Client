use ExtUtils::H2PM;

module "Couchbase::Client::IDXConst";
use_export;
$ENV{C_INCLUDE_PATH} = './';

include "sys/types.h";
include "perl-couchbase.h";
include "perl-couchbase-async.h";

my @const_bases = qw(
    CTORIDX_SERVERS
    CTORIDX_USERNAME
    CTORIDX_PASSWORD
    CTORIDX_BUCKET
    CTORIDX_STOREFLAGS
    CTORIDX_MYFLAGS
    
    CTORIDX_COMP_THRESHOLD
    CTORIDX_COMP_METHODS
    
    CTORIDX_SERIALIZE_METHODS
    
    RETIDX_VALUE
    RETIDX_ERRSTR
    RETIDX_CAS
    RETIDX_ERRNUM
);

constant("PLCB_$_", name => $_) for (@const_bases);

my @ctor_flags = qw(
    USE_COMPAT_FLAGS
    USE_COMPRESSION
    USE_STORABLE
    USE_CONVERT_UTF8
);

constant("PLCBf_$_", name => "f$_") for (@ctor_flags);

my @async_bases = qw(
    CTORIDX_CBEVMOD
    CTORIDX_CBERR
);

constant("PLCBA_$_", name => $_) for (@async_bases);

my @event_bases = qw(
    READ_EVENT
    WRITE_EVENT
);

constant("LIBCOUCHBASE_$_", name => "COUCHBASE_$_") for (@event_bases);


write_output($ARGV[0]);
