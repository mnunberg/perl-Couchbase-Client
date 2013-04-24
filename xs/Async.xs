#include "perl-couchbase-async.h"

MODULE = Couchbase::Client PACKAGE = Couchbase::Client::Async PREFIX = PLCBA_

SV *
PLCBA_construct(pkg, options)
    const char *pkg
    AV *options


SV *
PLCBA__get_base_rv(self)
    SV *self
    
    CODE:
    /*this returns the underlying 'base' object, for selected proxy-methods*/
    if (!SvROK(self)) {
        die("I was not given a reference");
    }
    RETVAL = newRV_inc(SvRV(self));
    
    OUTPUT:
    RETVAL

void
PLCBA_connect(self)
    SV* self

void
PLCBA_HaveEvent(pkg, flags, opaque)
    const char *pkg
    short flags
    SV *opaque
    
void
PLCBA__request2(self, cmdargs, cbargs)
    SV *self
    SV *cmdargs
    HV *cbargs

    ALIAS:
    get = PLCB_CMD_GET
    touch = PLCB_CMD_TOUCH
    lock = PLCB_CMD_LOCK
    set = PLCB_CMD_SET
    add = PLCB_CMD_ADD
    replace = PLCB_CMD_REPLACE
    append = PLCB_CMD_APPEND
    prepend = PLCB_CMD_PREPEND
    cas = PLCB_CMD_CAS
    remove = PLCB_CMD_REMOVE
    unlock = PLCB_CMD_UNLOCK

    get_multi = PLCB_CMD_MULTI_GET
    touch_multi = PLCB_CMD_MULTI_TOUCH
    lock_multi = PLCB_CMD_MULTI_LOCK
    set_multi = PLCB_CMD_MULTI_SET
    add_multi = PLCB_CMD_MULTI_ADD
    replace_multi = PLCB_CMD_MULTI_REPLACE
    append_multi = PLCB_CMD_MULTI_APPEND
    prepend_multi = PLCB_CMD_MULTI_PREPEND
    cas_multi = PLCB_CMD_MULTI_CAS
    remove_multi = PLCB_CMD_MULTI_REMOVE
    unlock_multi = PLCB_CMD_MULTI_UNLOCK

    CODE:
    PLCBA_request2(self, ix, cmdargs, cbargs);

void
PLCBA_command(self, cmd, cmdargs, cbargs)
    SV *self
    int cmd
    SV *cmdargs
    HV *cbargs

    CODE:
    PLCBA_request2(self, cmd, cmdargs, cbargs);
