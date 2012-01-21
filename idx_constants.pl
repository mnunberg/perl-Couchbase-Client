use ExtUtils::H2PM;

module "Couchbase::Client::IDXConst";
use_export;
$ENV{C_INCLUDE_PATH} = './';

include "sys/types.h";
include "perl-couchbase.h";
my @const_bases = qw(
    CTORIDX_SERVERS
    CTORIDX_USERNAME
    CTORIDX_PASSWORD
    CTORIDX_BUCKET
    CTORIDX_STOREFLAGS
    CTORIDX_MYFLAGS
    
    RETIDX_VALUE
    RETIDX_ERRSTR
    RETIDX_CAS
    RETIDX_ERRNUM
);

constant("PLCB_$_", name => $_) for (@const_bases);
write_output($ARGV[0]);
