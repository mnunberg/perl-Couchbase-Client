#include "perl-couchbase.h"
#include "plcb-commands.h"

#define MULTI_STACK_ELEM 64

PLCB_STRUCT_MAYBE_ALLOC_SIZED(syncs_maybe_alloc, PLCB_sync_t, 32);
PLCB_MAYBE_ALLOC_GENFUNCS(syncs_maybe_alloc, PLCB_sync_t, 32, static);


#define CMD_MAYBE_ALLOC(base, sname) \
    PLCB_STRUCT_MAYBE_ALLOC_SIZED(base##_maybe_alloc, sname, MULTI_STACK_ELEM); \
    PLCB_STRUCT_MAYBE_ALLOC_SIZED(base##P_maybe_alloc, const sname*, MULTI_STACK_ELEM); \
    PLCB_MAYBE_ALLOC_GENFUNCS(base##_maybe_alloc, sname, MULTI_STACK_ELEM, static); \
    PLCB_MAYBE_ALLOC_GENFUNCS(base##P_maybe_alloc, const sname*, MULTI_STACK_ELEM, static);


CMD_MAYBE_ALLOC(touchcmd, lcb_touch_cmd_t);
CMD_MAYBE_ALLOC(getcmd, lcb_get_cmd_t);

#ifndef mk_instance_vars
#define mk_instance_vars(sv, inst_name, obj_name) \
    if (!SvROK(sv)) { \
        die("self must be a reference"); \
    } \
    obj_name = NUM2PTR(PLCB_t*, SvIV(SvRV(sv))); \
    if(!obj_name) { \
        die("tried to access de-initialized PLCB_t"); \
    } \
    inst_name = obj_name->instance;

#endif

#define _fetch_assert(tmpsv, av, idx, diemsg) \
    if ( (tmpsv = av_fetch(av, idx, 0)) == NULL) { \
        die("%s (expected something at %d)", diemsg, idx); \
    }


#define _MULTI_INIT_COMMON(object, ret, nreq, args, now) \
    if ( (nreq = av_len(args) + 1) == 0 ) { \
        die("Need at least one spec"); \
    } \
    ret = newHV(); \
    SAVEFREESV(ret); \
    now = time(NULL); \
    av_clear(object->errors);

#define _SYNC_RESULT_INIT(object, hv, sync) \
    sync.ret = newAV(); \
    sync.type = PLCB_SYNCTYPE_SINGLE; \
    (void) hv_store(hv, sync.key, sync.nkey, \
                    plcb_ret_blessed_rv(object, sync.ret), 0); \
    sync.parent = object;


#define _exp_from_av(av, idx, nowvar, expvar, tmpsv) \
    if ( (tmpsv = av_fetch(av, idx, 0)) && (expvar = plcb_exp_from_sv(*tmpsv))) { \
        PLCB_UEXP2EXP(expvar, expvar, nowvar); \
    }

#define _cas_from_av(av, idx, casvar, tmpsv) \
    if ( (tmpsv = av_fetch(av, idx, 0)) && SvTRUE(*tmpsv) ) { \
        casvar = plcb_sv_to_u64(*tmpsv); \
    }

#define _MAYBE_SET_IMMEDIATE_ERROR(err, retav, waitvar) \
    if (err == LCB_SUCCESS) { \
        waitvar++; \
    } \
    else { \
        plcb_ret_set_err(object, retav, err); \
    }

#define _MAYBE_WAIT(waitvar) \
    if (waitvar) { \
        object->npending += waitvar; \
        plcb_evloop_start(object); \
    }

#define _dMULTI_VARS \
    PLCB_t *object; \
    lcb_t instance; \
    lcb_error_t err; \
    int nreq, i; \
    time_t now; \
    HV *ret;

static void
restore_single_callbacks(void *arg)
{
    PLCB_t *obj = (PLCB_t*)arg;
    plcb_callbacks_set_single(obj);
}

static SV*
PLCB_multi_get_common(SV *self, AV *args, int cmd)
{
    _dMULTI_VARS
    
    void **keys;
    size_t *sizes;
    time_t *exps;
    SV **tmpsv;
    PLCB_sync_t *syncp;
    int cmd_base;
    
    union {
        struct getcmd_maybe_alloc get;
        struct touchcmd_maybe_alloc touch;
    } u_cmd;

    union {
        struct getcmdP_maybe_alloc get;
        struct touchcmdP_maybe_alloc touch;
    } u_pcmd;

    mk_instance_vars(self, instance, object);
    _MULTI_INIT_COMMON(object, ret, nreq, args, now);
    
    syncp = &object->sync;
    syncp->parent = object;
    syncp->ret = (AV*)ret;
    
    cmd_base = (PLCB_COMMAND_MASK & cmd);


    if (cmd_base == PLCB_CMD_GET) {
        getcmd_maybe_alloc_init(&u_cmd.get, nreq);
        getcmdP_maybe_alloc_init(&u_pcmd.get, nreq);
        memset(u_cmd.get.bufp, 0, sizeof(lcb_get_cmd_t) * nreq);

    } else {
        touchcmd_maybe_alloc_init(&u_cmd.touch, nreq);
        touchcmdP_maybe_alloc_init(&u_pcmd.touch, nreq);
        memset(u_cmd.touch.bufp, 0, sizeof(lcb_touch_cmd_t) * nreq);
    }
    
#define do_free_buffers() \
        if (cmd_base == PLCB_CMD_GET) { \
            getcmd_maybe_alloc_cleanup(&u_cmd.get); \
            getcmdP_maybe_alloc_cleanup(&u_pcmd.get); \
        } else { \
            touchcmd_maybe_alloc_cleanup(&u_cmd.touch); \
            touchcmdP_maybe_alloc_cleanup(&u_pcmd.touch); \
        }

    for (i = 0; i < nreq; i++) {
        const char *curkey;
        size_t curklen;
        time_t curexp;

        _fetch_assert(tmpsv, args, i, "arguments");
        if (SvTYPE(*tmpsv) <= SVt_PV) {

            if (cmd_base == PLCB_CMD_TOUCH) {
                die("This command requires a valid expiry");
            }

            plcb_get_str_or_die(*tmpsv, curkey, curklen, "key");

        } else {
            AV *argav = NULL;
            if (SvROK(*tmpsv) == 0 ||
                    ( (argav = (AV*)SvRV(*tmpsv)) && SvTYPE(argav) != SVt_PVAV)) {
                die("Expected an array reference");
            }

            _fetch_assert(tmpsv, argav, 0, "missing key");
            
            plcb_get_str_or_die(*tmpsv, curkey, curklen, "key");
            

            if (cmd_base == PLCB_CMD_TOUCH) {
                _fetch_assert(tmpsv, argav, 1, "expiry");
                if (! (curexp = plcb_exp_from_sv(*tmpsv)) ) {
                    die("expiry of 0 passed. This is not what you want");
                }
            }
        }

        if (cmd_base == PLCB_CMD_GET) {
            lcb_get_cmd_t *curcmd = u_cmd.get.bufp + i;
            curcmd->v.v0.key = curkey;
            curcmd->v.v0.nkey = curklen;
            curcmd->v.v0.exptime = curexp;

            u_pcmd.get.bufp[i] = curcmd;

        } else {
            lcb_touch_cmd_t *curcmd = u_cmd.touch.bufp + i;
            curcmd->v.v0.key = curkey;
            curcmd->v.v0.nkey = curklen;
            curcmd->v.v0.exptime = curexp;

            u_pcmd.touch.bufp[i] = curcmd;
        }
    }
    
    /* Figure out if we're using an iterator or not */
    if (cmd & PLCB_COMMANDf_ITER) {
        SV *iter_ret;
        assert(cmd_base == PLCB_CMD_GET || cmd_base == PLCB_CMD_GAT);

        iter_ret = plcb_multi_iterator_new(object,
                                           self,
                                           u_pcmd.get.bufp,
                                           nreq);
        do_free_buffers();
        return iter_ret;
    }

    plcb_callbacks_set_multi(object);
    SAVEDESTRUCTOR(restore_single_callbacks, object);
    
    if (cmd == PLCB_CMD_TOUCH) {
        err = lcb_touch(instance, syncp, nreq, u_pcmd.touch.bufp);

    } else {
        err = lcb_get(instance, syncp, nreq, u_pcmd.get.bufp);
    }
    
    if (err == LCB_SUCCESS) {
        object->npending += nreq;
        plcb_evloop_start(object);

    } else {
        for (i = 0; i < nreq; i++) {
            const char *curkey;
            size_t curlen;
            if (cmd_base == PLCB_CMD_GET) {
                curkey = u_cmd.get.bufp[i].v.v0.key;
                curlen = u_cmd.get.bufp[i].v.v0.nkey;
            } else {
                curkey = u_cmd.touch.bufp[i].v.v0.key;
                curlen = u_cmd.touch.bufp[i].v.v0.nkey;
            }

            AV *errav = newAV();
            plcb_ret_set_err(object, errav, err);
            (void) hv_store(ret,
                    curkey, curlen,
                    plcb_ret_blessed_rv(object, errav),
                    0);
        }
    }

    do_free_buffers();

    return newRV_inc( (SV*)ret);
}

static SV*
PLCB_multi_set_common(SV *self, AV *args, int cmd)
{
    _dMULTI_VARS
    PLCB_sync_t *syncs = NULL;
    struct syncs_maybe_alloc syncs_buf;
    lcb_storage_t storop;
    plcb_conversion_spec_t conversion_spec = PLCB_CONVERT_SPEC_NONE;
    
    int nwait;
    int cmd_base;
    
    mk_instance_vars(self, instance, object);
    
    _MULTI_INIT_COMMON(object, ret, nreq, args, now);
    syncs_maybe_alloc_init(&syncs_buf, nreq);
    syncs = syncs_buf.bufp;
    
    cmd_base = cmd & PLCB_COMMAND_MASK;
    nwait = 0;
    storop = plcb_command_to_storop(cmd);
    
    if (cmd & PLCB_COMMANDf_COUCH) {
        conversion_spec = PLCB_CONVERT_SPEC_JSON;
    }
    
    for (i = 0; i < nreq; i++) {
        AV *argav = NULL;
        SV **tmpsv;
        char *value;
        STRLEN nvalue;
        SV *value_sv = NULL;
        uint32_t store_flags = 0;
        uint64_t cas = 0;
        time_t exp = 0;
        
        lcb_store_cmd_t cmd = { 0 };
        const lcb_store_cmd_t *cmdp = &cmd;

        _fetch_assert(tmpsv, args, i, "empty argument in spec");
        
        if (SvROK(*tmpsv) == 0 ||
                ( ((argav = (AV*)SvRV(*tmpsv)) && SvTYPE(argav) != SVt_PVAV))) {
            die("Expected array reference");
        }
        
        _fetch_assert(tmpsv, argav, 0, "expected key");
        plcb_get_str_or_die(*tmpsv, syncs[i].key, syncs[i].nkey, "key");
        _fetch_assert(tmpsv, argav, 1, "expected_value");
        plcb_get_str_or_die(*tmpsv, value, nvalue, "value");
        value_sv = *tmpsv;
        
        switch(cmd_base) {

        case PLCB_CMD_SET:
        case PLCB_CMD_ADD:
        case PLCB_CMD_REPLACE:
        case PLCB_CMD_APPEND:
        case PLCB_CMD_PREPEND:
            _exp_from_av(argav, 2, now, exp, tmpsv);
            _cas_from_av(argav, 3, cas, tmpsv);
            break;

        case PLCB_CMD_CAS:
            _fetch_assert(tmpsv, argav, 2, "Expected cas");
            _cas_from_av(argav, 2, cas, tmpsv);
            _exp_from_av(argav, 3, now, exp, tmpsv);
            break;

        default:
            die("Unhandled command %d", cmd);
        }
        
        _SYNC_RESULT_INIT(object, ret, syncs[i]);

        plcb_convert_storage(object,
                             &value_sv,
                             &nvalue,
                             &store_flags,
                             conversion_spec);
        
        cmd.v.v0.key = syncs[i].key;
        cmd.v.v0.nkey = syncs[i].nkey;
        cmd.v.v0.bytes = SvPVX(value_sv);
        cmd.v.v0.nbytes = nvalue;
        cmd.v.v0.flags = store_flags;
        cmd.v.v0.exptime = exp;
        cmd.v.v0.cas = cas;
        cmd.v.v0.operation = storop;

        err = lcb_store(instance, syncs + i, 1, &cmdp);
        
        plcb_convert_storage_free(object, value_sv, store_flags);
        
        _MAYBE_SET_IMMEDIATE_ERROR(err, syncs[i].ret, nwait);
        
    }

    _MAYBE_WAIT(nwait);

    syncs_maybe_alloc_cleanup(&syncs_buf);
    return newRV_inc( (SV*)ret);
}

static SV* PLCB_multi_arithmetic_common(SV *self, AV *args, int cmd)
{
    _dMULTI_VARS
    
    PLCB_sync_t *syncs;
    struct syncs_maybe_alloc syncs_buf;
    int nwait = 0;
    
    mk_instance_vars(self, instance, object);
    _MULTI_INIT_COMMON(object, ret, nreq, args, now);
    
    syncs_maybe_alloc_init(&syncs_buf, nreq);
    syncs = syncs_buf.bufp;

    for (i = 0; i < nreq; i++) {
        AV *argav = NULL;
        SV **tmpsv;
        time_t exp = 0;
        int64_t delta = 1;
        uint64_t initial = 0;
        int do_create = 0;
        
        lcb_arithmetic_cmd_t acmd = { 0 };
        const lcb_arithmetic_cmd_t *cmdp = &acmd;

        #define _do_arith_simple(only_sv) \
            plcb_get_str_or_die(only_sv, syncs[i].key, syncs[i].nkey, "key"); \
            delta = (cmd == PLCB_CMD_DECR) ? (-delta) : delta; \
            goto GT_CBC_CMD;
        
        _fetch_assert(tmpsv, args, i, "empty argument in spec");
        
        
        if (SvTYPE(*tmpsv) == SVt_PV) {
            /*simple key*/
            if (cmd == PLCB_CMD_ARITHMETIC) {
                die("Expected array reference!");
            }
            _do_arith_simple(*tmpsv);

        } else {
            if (SvROK(*tmpsv) == 0 ||
                    ( (argav = (AV*)SvRV(*tmpsv)) && SvTYPE(argav) != SVt_PVAV)) {
                die("Expected ARRAY reference");
            }
        }
        
        _fetch_assert(tmpsv, argav, 0, "expected key");
        
        if (av_len(argav) == 0) {
            _do_arith_simple(*tmpsv);

        } else {
            plcb_get_str_or_die(*tmpsv, syncs[i].key, syncs[i].nkey, "key");
        }
        
        _fetch_assert(tmpsv, argav, 1, "expected delta");
        delta = SvIV(*tmpsv);
        delta = (cmd == PLCB_CMD_DECR) ? (-delta) : delta;
        
        if (cmd != PLCB_CMD_ARITHMETIC) {
            goto GT_CBC_CMD;
        }
        
        /*fetch initial value here*/
        if ( (tmpsv = av_fetch(argav, 2, 0)) && SvTYPE(*tmpsv) != SVt_NULL ) {
            initial = SvUV(*tmpsv);
            do_create = 1;
        }
        
        if ( (tmpsv = av_fetch(argav, 3, 0)) && (exp = plcb_exp_from_sv(*tmpsv)) ) {
            PLCB_UEXP2EXP(exp, exp, now);
        }
        
        GT_CBC_CMD:
        
        _SYNC_RESULT_INIT(object, ret, syncs[i]);

        acmd.v.v0.key = syncs[i].key;
        acmd.v.v0.nkey = syncs[i].nkey;
        acmd.v.v0.delta = delta;
        acmd.v.v0.exptime = exp;
        acmd.v.v0.create = do_create;
        acmd.v.v0.initial = initial;

        err = lcb_arithmetic(instance, syncs + i, 1, &cmdp);

        _MAYBE_SET_IMMEDIATE_ERROR(err, syncs[i].ret, nwait);
        
    }
    
    _MAYBE_WAIT(nwait);
    syncs_maybe_alloc_cleanup(&syncs_buf);
    return newRV_inc( (SV*)ret);
}

static SV*
PLCB_multi_remove(SV *self, AV *args)
{
    _dMULTI_VARS
    PLCB_sync_t *syncs = NULL;
    struct syncs_maybe_alloc syncs_buf;
    
    int nwait = 0;

    mk_instance_vars(self, instance, object);
    _MULTI_INIT_COMMON(object, ret, nreq, args, now);
    
    syncs_maybe_alloc_init(&syncs_buf, nreq);
    syncs = syncs_buf.bufp;
    
    for (i = 0; i < nreq; i++) {
        AV *argav = NULL;
        SV **tmpsv;
        uint64_t cas = 0;
        lcb_remove_cmd_t cmd = { 0 };
        const lcb_remove_cmd_t *cmdp = &cmd;

        
        _fetch_assert(tmpsv, args, i, "empty arguments in spec");

        if (SvTYPE(*tmpsv) == SVt_PV) {
            plcb_get_str_or_die(*tmpsv, syncs[i].key, syncs[i].nkey, "key");

        } else {
            if(SvROK(*tmpsv) == 0 ||
                    ( (argav = (AV*)SvRV(*tmpsv)) && SvTYPE(argav) != SVt_PVAV)) {
                die("Expected ARRAY reference");
            }
            _fetch_assert(tmpsv, argav, 0, "key");
            plcb_get_str_or_die(*tmpsv, syncs[i].key, syncs[i].nkey, "key");
            _cas_from_av(argav, 1, cas, tmpsv);
        }
        
        _SYNC_RESULT_INIT(object, ret, syncs[i]);
        
        cmd.v.v0.key = syncs[i].key;
        cmd.v.v0.nkey = syncs[i].nkey;
        cmd.v.v0.cas = cas;

        err = lcb_remove(instance, syncs + i, 1, &cmdp);

        _MAYBE_SET_IMMEDIATE_ERROR(err, syncs[i].ret, nwait);
    }
    _MAYBE_WAIT(nwait);
    syncs_maybe_alloc_cleanup(&syncs_buf);
    return newRV_inc( (SV*)ret );
    
}

#define _MAYBE_MULTI_ARG2(array, always_wrap) \
    if (items == 2 && always_wrap == 0) { \
        array = (AV*)ST(1); \
        if ( SvROK((SV*)array) && (array = (AV*)SvRV((SV*)array))) { \
            if (SvTYPE(array) < SVt_PVAV) { \
                die("Expected ARRAY reference for arguments"); \
            } \
        } \
    } else if (items > 2 || items == 2 && always_wrap == 1) { \
        array = (AV*)sv_2mortal((SV*)av_make(items-1, (SP - items + 2))); \
    } else { \
        die("Usage: %s(self, args)", GvNAME(GvCV(cv))); \
    }

#define _MAYBE_MULTI_ARG(array) \
    _MAYBE_MULTI_ARG2(array, 0);

MODULE = Couchbase::Client_multi PACKAGE = Couchbase::Client    PREFIX = PLCB_

PROTOTYPES: DISABLE

SV* PLCB__get_multi(self, ...)
    SV *self
    
    ALIAS:
    touch_multi = PLCB_CMD_TOUCH
    gat_multi = PLCB_CMD_GAT
    get_multi = PLCB_CMD_GET
    get_iterator = PLCB_CMD_ITER_GET
    
    PREINIT:
    AV *args = NULL;
    
    CODE:
    _MAYBE_MULTI_ARG(args);
    
    RETVAL = PLCB_multi_get_common(self, args, ix);
    
    OUTPUT:
    RETVAL
    
SV*
PLCB__set_multi(self, ...)
    SV *self
    
    ALIAS:
    set_multi           = PLCB_CMD_SET
    add_multi           = PLCB_CMD_ADD
    replace_multi       = PLCB_CMD_REPLACE
    append_multi        = PLCB_CMD_APPEND
    prepend_multi       = PLCB_CMD_PREPEND
    cas_multi           = PLCB_CMD_CAS
    
    couch_add_multi     = PLCB_CMD_COUCH_ADD
    couch_set_multi     = PLCB_CMD_COUCH_SET
    couch_cas_multi     = PLCB_CMD_COUCH_CAS
    
    
    PREINIT:
    AV *args = NULL;
    
    CODE:
    _MAYBE_MULTI_ARG2(args, 1);
    RETVAL = PLCB_multi_set_common(self, args, ix);
    
    OUTPUT:
    RETVAL
    
SV*
PLCB__arithmetic_multi(self, ...)
    SV *self
    
    ALIAS:
    arithmetic_multi= PLCB_CMD_ARITHMETIC
    incr_multi      = PLCB_CMD_INCR
    decr_multi      = PLCB_CMD_DECR
    
    PREINIT:
    AV *args = NULL;
    
    CODE:
    _MAYBE_MULTI_ARG(args);
    RETVAL = PLCB_multi_arithmetic_common(self, args, ix);
    
    OUTPUT:
    RETVAL

SV*
PLCB_remove_multi(self, ...)
    SV *self
    
    ALIAS:
    delete_multi = 1
    
    PREINIT:
    AV *args = NULL;
    
    CODE:
    _MAYBE_MULTI_ARG(args);
    RETVAL = PLCB_multi_remove(self, args);
    
    OUTPUT:
    RETVAL
    
