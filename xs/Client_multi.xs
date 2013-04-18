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
PLCB_multi_get_common(SV *self, AV *speclist, int cmd)
{
    _dMULTI_VARS
    
    SV **tmpsv;
    PLCB_sync_t *syncp;
    int cmd_base;
    PLCB_argopts_t ao = { 0 };
    
    union {
        struct getcmd_maybe_alloc get;
        struct touchcmd_maybe_alloc touch;
    } u_cmd;

    union {
        struct getcmdP_maybe_alloc get;
        struct touchcmdP_maybe_alloc touch;
    } u_pcmd;

    mk_instance_vars(self, instance, object);
    _MULTI_INIT_COMMON(object, ret, nreq, speclist, now);
    
    syncp = &object->sync;
    syncp->parent = object;
    syncp->ret = (AV*)ret;

    cmd_base = (PLCB_COMMAND_MASK & cmd);

    ao.autodie = 1;
    ao.now = now;

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
        AV *curspec = NULL;
        SV *args[PLCB_ARGS_MAX];
        int speclen;

        _fetch_assert(tmpsv, speclist, i, "arguments");
        if (SvTYPE(*tmpsv) <= SVt_PV) {
            lcb_get_cmd_t *gcmd = u_cmd.get.bufp + i;

            if (cmd_base != PLCB_CMD_GET) {
                die("Bare-keys only work with get()");
            }
            
            plcb_get_str_or_die(*tmpsv,
                                gcmd->v.v0.key,
                                gcmd->v.v0.nkey,
                                "key");
            continue;
        }

        /**
         * Alright, we have an array
         */
        if (SvROK(*tmpsv) == 0 ||
                ( (curspec = (AV*)SvRV(*tmpsv)) && SvTYPE(curspec) != SVt_PVAV)) {
            die("Expected an array reference");
        }

        plcb_makeargs_av(args, curspec, &speclen);

        switch (cmd_base) {
        case PLCB_CMD_GET:
            PLCB_args_get(object,
                          args,
                          speclen,
                          u_cmd.get.bufp + i,
                          &ao);
            break;

        case PLCB_CMD_TOUCH:
            PLCB_args_touch(object,
                            args,
                            speclen,
                            u_cmd.touch.bufp + i,
                            &ao);
            break;

        case PLCB_CMD_LOCK:
            PLCB_args_lock(object,
                           args,
                           speclen,
                           u_cmd.get.bufp + i,
                           &ao);
            break;

        default:
            die("Got unknown cmd_base=%d", cmd_base);
            break;
        }
    }
    
    for (i = 0; i < nreq; i++) {
        if (cmd_base == PLCB_CMD_TOUCH) {
            u_pcmd.touch.bufp[i] = u_cmd.touch.bufp + i;
        } else {
            u_pcmd.get.bufp[i] = u_cmd.get.bufp + i;
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
PLCB_multi_set_common(SV *self, AV *speclist, int cmd)
{
    _dMULTI_VARS
    PLCB_sync_t *syncs = NULL;
    struct syncs_maybe_alloc syncs_buf;
    lcb_storage_t storop;
    plcb_conversion_spec_t conversion_spec = PLCB_CONVERT_SPEC_NONE;
    PLCB_argopts_t ao = { 0 };
    
    int nwait;
    int cmd_base;
    
    mk_instance_vars(self, instance, object);
    
    _MULTI_INIT_COMMON(object, ret, nreq, speclist, now);
    syncs_maybe_alloc_init(&syncs_buf, nreq);
    syncs = syncs_buf.bufp;
    
    cmd_base = cmd & PLCB_COMMAND_MASK;
    nwait = 0;
    storop = plcb_command_to_storop(cmd);
    ao.autodie = 1;
    ao.now = now;
    
    if (cmd & PLCB_COMMANDf_COUCH) {
        conversion_spec = PLCB_CONVERT_SPEC_JSON;
    }
    
    for (i = 0; i < nreq; i++) {
        AV *curspec = NULL;
        SV *args[PLCB_ARGS_MAX];
        int speclen;
        SV **tmpsv;
        char *value;
        STRLEN nvalue;
        SV *value_sv = NULL;
        uint32_t store_flags = 0;
        
        lcb_store_cmd_t cmd = { 0 };
        const lcb_store_cmd_t *cmdp = &cmd;

        _fetch_assert(tmpsv, speclist, i, "empty argument in spec");
        
        if (SvROK(*tmpsv) == 0 ||
                ( ((curspec = (AV*)SvRV(*tmpsv)) && SvTYPE(curspec) != SVt_PVAV))) {
            die("Expected array reference");
        }
        
        plcb_makeargs_av(args, curspec, &speclen);
        value_sv = args[1];
        plcb_get_str_or_die(value_sv, value, nvalue, "value");
        
        if (cmd_base == PLCB_CMD_CAS) {
            PLCB_args_cas(object, args, speclen, &cmd, &ao);

        } else {
            PLCB_APPEND_SANITY(cmd_base, value_sv);
            PLCB_args_set(object, args, speclen, &cmd, &ao);
        }
        
        syncs[i].key = cmd.v.v0.key;
        syncs[i].nkey = cmd.v.v0.nkey;

        _SYNC_RESULT_INIT(object, ret, syncs[i]);

        plcb_convert_storage(object,
                             &value_sv,
                             &nvalue,
                             &store_flags,
                             conversion_spec);
        
        cmd.v.v0.bytes = SvPVX(value_sv);
        cmd.v.v0.nbytes = nvalue;
        cmd.v.v0.flags = store_flags;
        cmd.v.v0.operation = storop;

        err = lcb_store(instance, syncs + i, 1, &cmdp);
        
        plcb_convert_storage_free(object, value_sv, store_flags);
        
        _MAYBE_SET_IMMEDIATE_ERROR(err, syncs[i].ret, nwait);
        
    }

    _MAYBE_WAIT(nwait);

    syncs_maybe_alloc_cleanup(&syncs_buf);
    return newRV_inc( (SV*)ret);
}

static SV* PLCB_multi_arithmetic_common(SV *self, AV *speclist, int cmd)
{
    _dMULTI_VARS
    
    PLCB_sync_t *syncs;
    struct syncs_maybe_alloc syncs_buf;
    int nwait = 0;
    PLCB_argopts_t ao = { 0 };
    mk_instance_vars(self, instance, object);
    _MULTI_INIT_COMMON(object, ret, nreq, speclist, now);
    
    syncs_maybe_alloc_init(&syncs_buf, nreq);
    syncs = syncs_buf.bufp;

    ao.autodie = 1;
    ao.now = now;

    for (i = 0; i < nreq; i++) {
        AV *curspec = NULL;
        SV **tmpsv;
        SV *args[PLCB_ARGS_MAX];
        int speclen;
        
        lcb_arithmetic_cmd_t acmd = { 0 };
        const lcb_arithmetic_cmd_t *cmdp = &acmd;
        
        _fetch_assert(tmpsv, speclist, i, "empty argument in spec");
        
        
        if (SvTYPE(*tmpsv) == SVt_PV) {
            /*simple key*/
            if (cmd == PLCB_CMD_ARITHMETIC) {
                die("Expected array reference!");
            }

            args[0] = *tmpsv;
            speclen = 1;
        } else {
            if (SvROK(*tmpsv) == 0 ||
                    ( (curspec = (AV*)SvRV(*tmpsv)) && SvTYPE(curspec) != SVt_PVAV)) {
                die("Expected ARRAY reference");
            }
            plcb_makeargs_av(args, curspec, &speclen);
        }
        
        if (cmd == PLCB_CMD_ARITHMETIC) {
            PLCB_args_arithmetic(object, args, speclen, &acmd, &ao);

        } else {
            PLCB_args_incrdecr(object, args, speclen, &acmd, &ao);
            if (cmd == PLCB_CMD_DECR) {
                acmd.v.v0.delta = (-acmd.v.v0.delta);
            }
        }
        
        syncs[i].key = acmd.v.v0.key;
        syncs[i].nkey = acmd.v.v0.nkey;
        
        _SYNC_RESULT_INIT(object, ret, syncs[i]);
        err = lcb_arithmetic(instance, syncs + i, 1, &cmdp);

        _MAYBE_SET_IMMEDIATE_ERROR(err, syncs[i].ret, nwait);
        
    }
    
    _MAYBE_WAIT(nwait);
    syncs_maybe_alloc_cleanup(&syncs_buf);
    return newRV_inc( (SV*)ret);
}

static SV*
PLCB_multi_remove(SV *self, AV *speclist)
{
    _dMULTI_VARS
    PLCB_sync_t *syncs = NULL;
    struct syncs_maybe_alloc syncs_buf;
    PLCB_argopts_t ao = { 0 };
    int nwait = 0;

    mk_instance_vars(self, instance, object);
    _MULTI_INIT_COMMON(object, ret, nreq, speclist, now);
    
    syncs_maybe_alloc_init(&syncs_buf, nreq);
    syncs = syncs_buf.bufp;
    
    for (i = 0; i < nreq; i++) {
        AV *curspec = NULL;
        SV **tmpsv;
        SV *args[PLCB_ARGS_MAX];
        int speclen;
        lcb_remove_cmd_t cmd = { 0 };
        const lcb_remove_cmd_t *cmdp = &cmd;

        
        _fetch_assert(tmpsv, speclist, i, "empty arguments in spec");

        if (SvTYPE(*tmpsv) == SVt_PV) {
            args[0] = *tmpsv;
            speclen = 1;

        } else {
            if(SvROK(*tmpsv) == 0 ||
                    ( (curspec = (AV*)SvRV(*tmpsv)) && SvTYPE(curspec) != SVt_PVAV)) {
                die("Expected ARRAY reference");
            }
            plcb_makeargs_av(args, curspec, &speclen);
        }
        
        PLCB_args_remove(object, args, speclen, &cmd, &ao);
        syncs[i].key = cmd.v.v0.key;
        syncs[i].nkey = cmd.v.v0.nkey;

        _SYNC_RESULT_INIT(object, ret, syncs[i]);
        
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
    
