#!/usr/bin/perl
use PLCB_ConfUtil;
BEGIN {
    PLCB_ConfUtil::env_from_tmpflags();
}

use ExtUtils::H2PM;
module "Couchbase::Constants";
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
    CLIENT_ETMPFAIL
    KEY_EEXISTS
    KEY_ENOENT
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
    constant('LCB_'.$cbase, name => 'COUCHBASE_'.$cbase);
}

write_output $ARGV[0];
