#include "perl-couchbase-async.h"
#include "plcb-util.h"
#include "plcb-multi.h"

#define _mk_common_vars(selfsv, v_instance, v_base, v_async) \
    if( (!SvROK(selfsv)) || (!SvIOK(SvRV(selfsv))) ) \
        die("Passed a bad object!"); \
    v_async = NUM2PTR(PLCBA_t*, SvIV(SvRV(selfsv))); \
    v_base = &(v_async->base); \
    v_instance = v_base->instance;


static void init_async_cookie(PLCBA_t *async,
                              PLCBA_cookie_t **cookiep,
                              HV *cbparams)
{
    SV **cv;
    SV **data;
    SV **cbtype;
    PLCBA_cookie_t *cookie;

    cv = hv_fetchs(cbparams, "callback", 0);
    data = hv_fetchs(cbparams, "data", 0);
    cbtype = hv_fetchs(cbparams, "type", 0);

    if (!cv || SvTYPE(*cv) == SVt_NULL) {
        die("Must have callback");
    }

    Newxz(cookie, 1, PLCBA_cookie_t);
    *cookiep = cookie;

    cookie->parent = async;
    cookie->results = newHV();
    SAVEFREESV(cookie->results);

    cookie->callcb = *cv;
    (void) SvREFCNT_inc(cookie->callcb);

    if (data) {
        cookie->cbdata = *data;
        (void) SvREFCNT_inc(cookie->cbdata);
    }

    if (cbtype && SvTYPE(*cbtype) != SVt_NULL) {
        cookie->cbtype = SvIV(*cbtype);
        if (cookie->cbtype != PLCBA_CBTYPE_COMPLETION
                && cookie->cbtype != PLCBA_CBTYPE_INCREMENTAL) {
            die("Unrecognized callback type");
        }
    }

    (void) SvREFCNT_inc_NN(cookie->results);
}

AV *get_speclist(int cmd, SV *cmdargs)
{
    int cmd_base = cmd & PLCB_COMMAND_MASK;
    int is_multi = cmd & PLCB_COMMANDf_MULTI;
    AV *ret = NULL;

    /**
     * If argument is a simple scalar, wrap it inside an array for those commands
     * which permit it. Otherwise, just die.
     */
    if (SvROK(cmdargs) == 0 && SvPOK(cmdargs)) {
        switch (cmd_base) {
        case PLCB_CMD_GET:
        case PLCB_CMD_REMOVE:
        case PLCB_CMD_INCR:
        case PLCB_CMD_DECR: {
            ret = newAV();
            SAVEFREESV(ret);
            (void) SvREFCNT_inc(cmdargs);
            av_push(ret, cmdargs);
            return (AV*)ret;
        }

        default:
            die("Cannot use simple scalars for commands "
                    "that need > 1 argument. Command was %d", cmd_base);
            return NULL; /* not reached */
        }
    }

    if (SvROK(cmdargs) == 0 || SvTYPE(SvRV(cmdargs)) != SVt_PVAV) {
        die("Command arguments is a reference, but not of ARRAY. CMD=%d", cmd_base);
    }

    if (!is_multi) {
        ret = newAV();
        SAVEFREESV(ret);
        (void) SvREFCNT_inc(cmdargs);
        av_push(ret, cmdargs);

    } else {
        ret = (AV*)SvRV(cmdargs);
    }

    return ret;
}

void
PLCBA_request2(SV *self, int cmd, SV *cmdargs, HV *cbargs)
{
    PLCBA_t *async;
    PLCBA_cookie_t *cookie;
    AV *speclist;

    int cmd_base = cmd & PLCB_COMMAND_MASK;

    if( (!SvROK(self)) || (!SvIOK(SvRV(self))) ) {
        die("Passed a bad object!");
    }

    async = NUM2PTR(PLCBA_t*, SvIV(SvRV(self)));
    speclist = get_speclist(cmd, cmdargs);
    init_async_cookie(async, &cookie, cbargs);
    cookie->remaining = av_len(speclist) + 1;


    switch (cmd_base) {

    case PLCB_CMD_GET:
    case PLCB_CMD_TOUCH:
    case PLCB_CMD_LOCK:
        PLCB_multi_get_common(NULL, speclist, cmd, cookie);
        break;

    case PLCB_CMD_SET:
    case PLCB_CMD_ADD:
    case PLCB_CMD_REPLACE:
    case PLCB_CMD_APPEND:
    case PLCB_CMD_PREPEND:
    case PLCB_CMD_CAS:
        PLCB_multi_set_common(NULL, speclist, cmd, cookie);
        break;

    case PLCB_CMD_ARITHMETIC:
    case PLCB_CMD_INCR:
    case PLCB_CMD_DECR:
        PLCB_multi_arithmetic_common(NULL, speclist, cmd, cookie);
        break;

    case PLCB_CMD_REMOVE:
        PLCB_multi_remove(NULL, speclist, cookie);
        break;

    default:
        die("This command (%d) not implemented yet", cmd_base);
        break;

    }
}

static void extract_async_options(PLCBA_t *async, AV *options)
{
    #define _assert_get_cv(idxbase, target, diemsg) \
        if( (tmpsv = av_fetch(options, PLCBA_CTORIDX_ ## idxbase, 0)) == NULL \
            || SvTYPE(*tmpsv) == SVt_NULL) { \
            die("Must have '%s' callback", diemsg); \
        } \
        (void)SvREFCNT_inc(*tmpsv); \
        async->target = *tmpsv;
    
    SV **tmpsv;
    
    _assert_get_cv(CBEVMOD, cv_evmod, "update_event");
    _assert_get_cv(CBERR, cv_err, "error");
    _assert_get_cv(CBWAITDONE, cv_waitdone, "waitdone");
    _assert_get_cv(CBTIMERMOD, cv_timermod, "update_timer");
    
    if( (tmpsv = av_fetch(options, PLCBA_CTORIDX_BLESS_EVENT, 0)) ) {
        if(SvTRUE(*tmpsv)) {
            async->event_stash = gv_stashpv(PLCBA_EVENT_CLASS, 0);
        }
    }
    
    #undef _assert_get_cv
}

SV* PLCBA_construct(const char *pkg, AV *options)
{
    PLCBA_t *async;
    char *host, *username, *password, *bucket;
    lcb_t instance = NULL;
    SV *blessed_obj;
    struct lcb_create_st cr_opts = { 0 };
    
    Newxz(async, 1, PLCBA_t);
    
    extract_async_options(async, options);
    
    plcb_ctor_conversion_opts(&async->base, options);
    
    plcb_ctor_cbc_opts(options, &host, &username, &password, &bucket);

    cr_opts.v.v0.bucket = bucket;
    cr_opts.v.v0.host = host;
    cr_opts.v.v0.user = username;
    cr_opts.v.v0.passwd = password;
    cr_opts.v.v0.io = plcba_make_io_opts(async);

    lcb_create(&instance, &cr_opts);

    if(!instance) {
        die("Couldn't create instance!");
    }
    
    plcb_ctor_init_common(&async->base, instance, options);
    plcba_setup_callbacks(async);
    async->base_rv = newRV_inc(newSViv(PTR2IV(&(async->base))));
    
    blessed_obj = newSV(0);
    sv_setiv(newSVrv(blessed_obj, pkg), PTR2IV(async));
    return blessed_obj;
}

/*called from perl when an event arrives*/
void PLCBA_HaveEvent(const char *pkg, short flags, SV *opaque)
{
    /*TODO: optmize this to take an arrayref, and maybe configure ourselves for
     event loops which have a different calling convention, e.g. POE*/
    
    PLCBA_c_event *cevent;
    //sv_dump(opaque);
    
    cevent = NUM2PTR(PLCBA_c_event*, SvIV(opaque));
    cevent->c.handler(cevent->fd, flags, cevent->c.arg);
}

void PLCBA_connect(SV *self)
{
    lcb_t instance;
    PLCBA_t *async;
    PLCB_t *base;
    lcb_error_t err;
    
    _mk_common_vars(self, instance, base, async);
    if( (err = lcb_connect(instance)) != LCB_SUCCESS) {
        die("Problem with initial connection: %s (%d)",
            lcb_strerror(instance, err), err);
    }
    lcb_wait(instance);
}

/**
 * Apparently this function isn't used?
 */
void PLCBA_DESTROY(SV *self)
{
    PLCBA_t *async;
    lcb_t instance;
    PLCB_t *base;
    _mk_common_vars(self, instance, base, async);

    (void)instance;

    #define _DEC_AND_NULLIFY(fld) \
        if(async->fld) { SvREFCNT_dec(async->fld); async->fld = NULL; }
    
    _DEC_AND_NULLIFY(base_rv);
    _DEC_AND_NULLIFY(cv_evmod);
    _DEC_AND_NULLIFY(cv_timermod);
    _DEC_AND_NULLIFY(cv_err);
    _DEC_AND_NULLIFY(cv_waitdone);
    
    #undef _DEC_AND_NULLIFY
    
    /*cleanup our base object. This will also cause the events to be destroyed*/
    plcb_cleanup(&async->base);
    Safefree(async);
}
