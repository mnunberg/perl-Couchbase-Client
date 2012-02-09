use ExtUtils::H2PM;
use PLCB_ConfUtil;
PLCB_ConfUtil::set_gcc_env();

module "Couchbase::Client::Errors";
use_export;

include "sys/types.h";
include "libcouchbase/couchbase.h";
my @constant_basenames = qw(
    SUCCESS
    AUTH_CONTINUE
    AUTH_ERROR
    DELTA_BADVAL
    E2BIG
    EBUSY
    EINTERNAL
    EINVAL
    ENOMEM
    ERANGE
    ERROR
    ETMPFAIL
    KEY_EEXISTS
    KEY_ENOENT
    LIBEVENT_ERROR
    NETWORK_ERROR
    NOT_MY_VBUCKET
    NOT_STORED
    NOT_SUPPORTED
    UNKNOWN_COMMAND
    UNKNOWN_HOST
    PROTOCOL_ERROR
    ETIMEDOUT
    CONNECT_ERROR
    BUCKET_ENOENT
);
foreach my $cbase (@constant_basenames) {
    constant('LIBCOUCHBASE_'.$cbase, name => 'COUCHBASE_'.$cbase);
}

write_output $ARGV[0];
