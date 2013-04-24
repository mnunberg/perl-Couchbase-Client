#include "perl-couchbase.h"
#include "plcb-commands.h"
#include "perl-couchbase-async.h"

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

#define _SYNC_RESULT_INIT(object, hv, sync) \
    sync.ret = newAV(); \
    sync.type = PLCB_SYNCTYPE_SINGLE; \
    (void) hv_store(hv, sync.key, sync.nkey, \
                    plcb_ret_blessed_rv(object, sync.ret), 0); \
    sync.parent = object;

#define _MAYBE_WAIT(waitvar) \
    if (waitvar) { \
        assert(mi.object->npending == 0); \
        mi.object->npending += waitvar; \
        plcb_evloop_start(mi.object); \
    }


#define RETURN_COMMON(mi, ac, nwait) \
    if (ac) { \
        lcb_wait((mi)->instance); \
        return NULL; \
    } \
    _MAYBE_WAIT(nwait); \
    syncs_maybe_alloc_cleanup(&(mi)->syncs_buf); \
    return newRV_inc( (SV*)(mi)->ret );

typedef struct {
    PLCB_t *object;
    lcb_t instance;
    int nreq;
    time_t now;
    HV *ret;
    struct syncs_maybe_alloc syncs_buf;
    PLCB_sync_t *syncs;
} multi_info;

static void
restore_single_callbacks(void *arg)
{
    PLCB_t *obj = (PLCB_t*)arg;
    plcb_callbacks_set_single(obj);
}


static void init_mi(SV *self,
                    PLCBA_cookie_t *async_cookie,
                    AV *speclist,
                    multi_info *mi)
{
    mi->nreq = av_len(speclist) + 1;
    if (!mi->nreq) {
        die("Need at least one spec in list");
    }

    if (!async_cookie) {
        mk_instance_vars(self, mi->instance, mi->object);
        av_clear(mi->object->errors);
        mi->ret = newHV();
        SAVEFREESV(mi->ret);
        syncs_maybe_alloc_init(&mi->syncs_buf, mi->nreq);
        mi->syncs = mi->syncs_buf.bufp;

    } else {
        async_cookie->remaining = mi->nreq;
        mi->object = &async_cookie->parent->base;
        mi->instance = mi->object->instance;
    }

    mi->now = time(NULL);

}

/**
 * Get/Touch is a special case since we gain efficiency by batching commands
 * and terminating them with a no-op. For all other commands, we still gain
 * a lot of efficiency, but scheduling is a bit more complex.
 */
SV*
PLCB_multi_get_common(SV *self, AV *speclist, int cmd, PLCBA_cookie_t *async_cookie)
{
    PLCB_t *object;
    lcb_t instance;
    lcb_error_t err;
    int nreq;
    int i;
    time_t now;
    HV *ret;
    SV **tmpsv;
    void *our_cookie;
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

    nreq = av_len(speclist) + 1;
    now = time(NULL);

    if (!async_cookie) {
        mk_instance_vars(self, instance, object);

        av_clear(object->errors);
        ret = newHV();
        SAVEFREESV(ret);

        syncp = &object->sync;
        syncp->parent = object;
        syncp->ret = (AV*)ret;
        our_cookie = syncp;

    } else {
        our_cookie = async_cookie;
        async_cookie->remaining = nreq;
        object = &async_cookie->parent->base;
        instance = object->instance;
    }

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

        if (!SvROK(*tmpsv)) {
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

    if (!async_cookie) {
        plcb_callbacks_set_multi(object);
        SAVEDESTRUCTOR(restore_single_callbacks, object);
    }

    if (cmd == PLCB_CMD_TOUCH) {
        err = lcb_touch(instance, our_cookie, nreq, u_pcmd.touch.bufp);

    } else {
        err = lcb_get(instance, our_cookie, nreq, u_pcmd.get.bufp);
    }

    if (err == LCB_SUCCESS) {
        if (!async_cookie) {
            object->npending += nreq;
            plcb_evloop_start(object);
        } else {
            lcb_wait(instance);
        }

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

            if (!async_cookie) {
                AV *errav = newAV();
                plcb_ret_set_err(object, errav, err);
                (void) hv_store(ret,
                        curkey, curlen,
                        plcb_ret_blessed_rv(object, errav),
                        0);

            } else {
                plcba_callback_notify_err(async_cookie->parent,
                                          async_cookie,
                                          curkey,
                                          curlen,
                                          err);
            }
        }
    }

    do_free_buffers();


    if (!async_cookie) {
        return newRV_inc( (SV*)ret);
    }

    return NULL;
}

SV*
PLCB_multi_set_common(SV *self, AV *speclist, int cmd, PLCBA_cookie_t *async_cookie)
{
    lcb_storage_t storop;
    plcb_conversion_spec_t conversion_spec = PLCB_CONVERT_SPEC_NONE;
    PLCB_argopts_t ao = { 0 };
    multi_info mi = { 0 };
    int nwait = 0;
    int cmd_base;
    int ii;
    
    init_mi(self, async_cookie, speclist, &mi);

    cmd_base = cmd & PLCB_COMMAND_MASK;
    storop = plcb_command_to_storop(cmd);
    ao.autodie = 1;
    ao.now = mi.now;
    
    if (cmd & PLCB_COMMANDf_COUCH) {
        conversion_spec = PLCB_CONVERT_SPEC_JSON;
    }
    
    for (ii = 0; ii < mi.nreq; ii++) {
        AV *curspec = NULL;
        SV *args[PLCB_ARGS_MAX];
        int speclen;
        SV **tmpsv;
        char *value;
        STRLEN nvalue;
        SV *value_sv = NULL;
        uint32_t store_flags = 0;
        lcb_error_t err;
        
        lcb_store_cmd_t cmd = { 0 };
        const lcb_store_cmd_t *cmdp = &cmd;

        _fetch_assert(tmpsv, speclist, ii, "empty argument in spec");
        
        if (SvROK(*tmpsv) == 0 ||
                ( ((curspec = (AV*)SvRV(*tmpsv)) && SvTYPE(curspec) != SVt_PVAV))) {
            die("Expected array reference");
        }
        
        plcb_makeargs_av(args, curspec, &speclen);
        value_sv = args[1];
        plcb_get_str_or_die(value_sv, value, nvalue, "value");
        
        if (cmd_base == PLCB_CMD_CAS) {
            PLCB_args_cas(mi.object, args, speclen, &cmd, &ao);

        } else {
            PLCB_APPEND_SANITY(cmd_base, value_sv);
            PLCB_args_set(mi.object, args, speclen, &cmd, &ao);
        }
        
        plcb_convert_storage(mi.object,
                             &value_sv,
                             &nvalue,
                             &store_flags,
                             conversion_spec);
        
        cmd.v.v0.bytes = SvPVX(value_sv);
        cmd.v.v0.nbytes = nvalue;
        cmd.v.v0.flags = store_flags;
        cmd.v.v0.operation = storop;

        if (async_cookie == NULL) {
            mi.syncs[ii].key = cmd.v.v0.key;
            mi.syncs[ii].nkey = cmd.v.v0.nkey;
            _SYNC_RESULT_INIT(mi.object, mi.ret, mi.syncs[ii]);
            err = lcb_store(mi.instance, mi.syncs + ii, 1, &cmdp);

            if (err == LCB_SUCCESS) {
                nwait++;
            } else {
                plcb_ret_set_err(mi.object, mi.syncs[ii].ret, err);
            }

        } else {
            err = lcb_store(mi.instance, async_cookie, 1, &cmdp);
            if (err != LCB_SUCCESS) {
                plcba_callback_notify_err(async_cookie->parent,
                                          async_cookie,
                                          cmd.v.v0.key,
                                          cmd.v.v0.nkey,
                                          err);
            }
        }

        plcb_convert_storage_free(mi.object, value_sv, store_flags);
    }

    RETURN_COMMON(&mi, async_cookie, nwait);
}

SV*
PLCB_multi_arithmetic_common(SV *self,
                             AV *speclist,
                             int cmd,
                             PLCBA_cookie_t *async_cookie)
{
    int ii;
    int nwait = 0;
    PLCB_argopts_t ao = { 0 };
    multi_info mi = { 0 };
    init_mi(self, async_cookie, speclist, &mi);
    
    ao.autodie = 1;
    ao.now = mi.now;

    for (ii = 0; ii < mi.nreq; ii++) {
        AV *curspec = NULL;
        SV **tmpsv;
        SV *args[PLCB_ARGS_MAX];
        int speclen;
        lcb_error_t err;
        
        lcb_arithmetic_cmd_t acmd = { 0 };
        const lcb_arithmetic_cmd_t *cmdp = &acmd;
        
        _fetch_assert(tmpsv, speclist, ii, "empty argument in spec");
        
        
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
            PLCB_args_arithmetic(mi.object, args, speclen, &acmd, &ao);

        } else if (cmd == PLCB_CMD_INCR) {
            PLCB_args_incr(mi.object, args, speclen, &acmd, &ao);

        } else {
            PLCB_args_decr(mi.object, args, speclen, &acmd, &ao);
        }
        
        if (!async_cookie) {
            mi.syncs[ii].key = acmd.v.v0.key;
            mi.syncs[ii].nkey = acmd.v.v0.nkey;
            _SYNC_RESULT_INIT(mi.object, mi.ret, mi.syncs[ii]);
            err = lcb_arithmetic(mi.instance, mi.syncs + ii, 1, &cmdp);

            if (err != LCB_SUCCESS) {
                plcb_ret_set_err(mi.object, mi.syncs[ii].ret, err);

            } else {
                nwait++;
            }

        } else {
            err = lcb_arithmetic(mi.instance, async_cookie, 1, &cmdp);

            if (err != LCB_SUCCESS) {
                plcba_callback_notify_err(async_cookie->parent,
                                          async_cookie,
                                          acmd.v.v0.key,
                                          acmd.v.v0.nkey,
                                          err);
            }
        }
    }
    
    RETURN_COMMON(&mi, async_cookie, nwait);
}

SV*
PLCB_multi_remove(SV *self, AV *speclist, PLCBA_cookie_t *async_cookie)
{
    multi_info mi = { 0 };
    PLCB_argopts_t ao = { 0 };
    int nwait = 0;
    int ii;
    
    init_mi(self, async_cookie, speclist, &mi);
    
    for (ii = 0; ii < mi.nreq; ii++) {
        AV *curspec = NULL;
        SV **tmpsv;
        SV *args[PLCB_ARGS_MAX];
        int speclen;
        lcb_remove_cmd_t cmd = { 0 };
        const lcb_remove_cmd_t *cmdp = &cmd;
        lcb_error_t err;

        
        _fetch_assert(tmpsv, speclist, ii, "empty arguments in spec");

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
        
        PLCB_args_remove(mi.object, args, speclen, &cmd, &ao);
        
        if (!async_cookie) {
            mi.syncs[ii].key = cmd.v.v0.key;
            mi.syncs[ii].nkey = cmd.v.v0.nkey;
            _SYNC_RESULT_INIT(mi.object, mi.ret, mi.syncs[ii]);
            err = lcb_remove(mi.instance, mi.syncs + ii, 1, &cmdp);
            if (err == LCB_SUCCESS) {
                nwait++;
                continue;
            } else {
                plcb_ret_set_err(mi.object, mi.syncs[ii].ret, err);
            }
        } else {
            err = lcb_remove(mi.instance, async_cookie, 1, &cmdp);
            if (err != LCB_SUCCESS) {
                plcba_callback_notify_err(async_cookie->parent,
                                          async_cookie,
                                          cmd.v.v0.key,
                                          cmd.v.v0.nkey,
                                          err);
            }
        }
    }
    
    RETURN_COMMON(&mi, async_cookie, nwait);
}

#define _MAYBE_MULTI_ARG2(array, always_wrap) \
    if (items == 2 && always_wrap == 0) { \
        array = (AV*)ST(1); \
        if ( SvROK((SV*)array) && (array = (AV*)SvRV((SV*)array))) { \
            if (SvTYPE(array) < SVt_PVAV) { \
                die("Expected ARRAY reference for arguments"); \
            } \
        } \
    } else if (items > 2 || (items == 2 && always_wrap == 1)) { \
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
    
    RETVAL = PLCB_multi_get_common(self, args, ix, NULL);
    
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
    RETVAL = PLCB_multi_set_common(self, args, ix, NULL);
    
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
    RETVAL = PLCB_multi_arithmetic_common(self, args, ix, NULL);
    
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
    RETVAL = PLCB_multi_remove(self, args, NULL);
    
    OUTPUT:
    RETVAL
    
