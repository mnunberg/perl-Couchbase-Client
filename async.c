#include "perl-couchbase-async.h"
#include "plcb-util.h"

#ifndef _WIN32
#include <libcouchbase/libevent_io_opts.h>
#define plcba_default_io_opts() \
    libcouchbase_create_libevent_io_opts(NULL)

#else

#include <libcouchbase/winsock_io_opts.h>
#define plcba_default_io_opts() \
    libcouchbase_create_winsock_io_opts()

#endif

static void *create_event(plcba_cbcio *cbcio)
{
    PLCBA_c_event *cevent;
    Newxz(cevent, 1, PLCBA_c_event);
    return cevent;
}

static void destroy_event(plcba_cbcio *cbcio, void *event)
{
    PLCBA_c_event *cevent = (PLCBA_c_event*)event;
    if(cevent->dupfh) {
        SvREFCNT_dec(cevent->dupfh);
        cevent->dupfh = NULL;
    }
    Safefree(cevent);
}

/*start select()ing on a socket*/
static int update_event(plcba_cbcio *cbcio,
                        libcouchbase_socket_t sock,
                        void *event,
                        short flags,
                        void *cb_data,
                        plcba_c_evhandler handler)
{
    AV *fdes_av;
    PLCBA_t *object;
    SV *opaque_sv;
    SV *sock_sv;
    SV **dupfh_new;
    
    PLCBA_c_event *cevent;
    
    dSP;
    
    warn("Update event requested..");
    
    cevent = (PLCBA_c_event*)event;
    object = (PLCBA_t*)(cbcio->cookie);
    
    fdes_av = newAV();
    opaque_sv = newSViv(PTR2IV(cevent));
    sock_sv = newSVuv(sock);
    dupfh_new = NULL;
    
    av_store(fdes_av, 0, newSViv(sock));
    
    if(cevent->dupfh) {
        SvREFCNT_inc(cevent->dupfh);
        av_store(fdes_av, 1, cevent->dupfh);
    }
    
    cevent->c.handler = handler;
    cevent->c.arg = cb_data;
    
    /*BEGIN SUBROUTINE CALL*/
    ENTER;
    SAVETMPS;
    
    PUSHMARK(SP);
    XPUSHs(sv_2mortal(newRV_inc((SV*)fdes_av)));
    XPUSHs(sv_2mortal(newSViv(flags)));
    XPUSHs(sv_2mortal(opaque_sv));
    PUTBACK;
    
    call_sv(object->cv_evmod, G_DISCARD);
    
    
    if(!cevent->dupfh) {
        if( (dupfh_new = av_fetch(fdes_av, 1, 0))
           && SvTYPE(*dupfh_new) != SVt_NULL) {
            SvREFCNT_inc(*dupfh_new);
            cevent->dupfh = *dupfh_new;
        }
    } else {
        if( (dupfh_new = av_fetch(fdes_av, 0, 0)) == NULL ||
           SvTYPE(*dupfh_new) == SVt_NULL) {
            SvREFCNT_dec(cevent->dupfh);
            cevent->dupfh = NULL;
        }
    }
    
    FREETMPS;
    LEAVE;
    /*END SUBROUTINE CALL*/
    
    if(flags && (dupfh_new = av_fetch(fdes_av, 1, 0)) &&
       *dupfh_new != cevent->dupfh) {
        
        if(cevent->dupfh) {
            SvREFCNT_dec(cevent->dupfh);
            cevent->dupfh = *dupfh_new;
            SvREFCNT_inc(*dupfh_new);
        }
    } else if(flags == 0 && cevent->dupfh) {
        SvREFCNT_dec(cevent->dupfh);
        cevent->dupfh = NULL;
    }
    
    SvREFCNT_dec(fdes_av);
}

/*stop select()ing a socket*/
static void delete_event(plcba_cbcio *cbcio,
                         libcouchbase_socket_t sock, void *event)
{
    update_event(cbcio, sock, event, 0, NULL, NULL);
}

/*run/stop functions are noop because we are only running inside a cooperative
  event loop, and not driving it per se
*/
static void run_event_loop(plcba_cbcio *cbcio)
{
    /*noop?*/
}

static void stop_event_loop(plcba_cbcio *cbcio)
{
    /*noop*/
}

#define _mk_common_vars(selfsv, v_instance, v_base, v_async) \
    if( (!SvROK(selfsv)) || (!SvIOK(SvRV(selfsv))) ) \
        die("Passed a bad object!"); \
    v_async = NUM2PTR(PLCBA_t*, SvIV(SvRV(selfsv))); \
    v_base = &(v_async->base); \
    v_instance = v_base->instance;

static inline void av2request(
    PLCBA_t *async, PLCBA_cmd_t cmd,
    AV *reqav, struct PLCBA_request_st *request)
{
    #define _fetch_nonull(idx) \
        ((tmpsv = av_fetch(reqav, idx, 0)) && SvTYPE(*tmpsv) != SVt_NULL)
    #define _fetch_assert(idx, diemsg) \
        if((tmpsv = av_fetch(reqav, idx, 0)) == NULL) { die(diemsg); }
    
    #define _extract_exp() \
        request->exp = 0; \
        if((_fetch_nonull(PLCBA_REQIDX_EXP)) && SvIOK(*tmpsv) \
            && SvUV(*tmpsv) > 0) \
                { request->exp = time(NULL) + SvUV(*tmpsv); }
    
    SV **tmpsv;
    STRLEN dummy;
    char *dummystr;
    uint64_t *dummy_cas;
    
    if(plcba_cmd_needs_key(cmd)) {
        _fetch_assert(PLCBA_REQIDX_KEY, "Expected key but none passed");
        plcb_get_str_or_die(*tmpsv, request->key, request->nkey, "key");
    }

    _extract_exp();
    
    if(plcba_cmd_needs_strval(cmd)) {
        _fetch_assert(PLCBA_REQIDX_VALUE, "Expected value but none passed");
        request->value = *tmpsv;
        request->nvalue = SvLEN(*tmpsv);
        
        if(!request->nvalue) {
            die("Got zero-length value");
        }
        
        
        if(plcba_cmd_needs_conversion(cmd)) {
            request->has_conversion = 1;
            plcb_convert_storage(&(async->base),
                                 &(request->value), &(request->nvalue),
                                 &(request->store_flags));
        }
    } else if(cmd == PLCBA_CMD_ARITHMETIC) {
        if( (tmpsv = av_fetch(reqav, PLCBA_REQIDX_ARITH_DELTA, 0)) == NULL) {
            die("Arithmetic operation requested but no value specified");
        }
        request->arithmetic.delta = plcb_sv_to_64(*tmpsv);
        
        if( _fetch_nonull(PLCBA_REQIDX_ARITH_INITIAL) ) {
            request->arithmetic.initial = plcb_sv_to_u64(*tmpsv);
            request->arithmetic.create = 1;
        } else {
            request->arithmetic.create = 0;
        }
    }
    
    if( _fetch_nonull(PLCBA_REQIDX_CAS) ) {
        plcb_cas_from_sv(*tmpsv, dummy_cas, dummy);
        request->cas = *dummy_cas;
    }
#undef _fetch_nonull
#undef _fetch_assert
#undef _extract_exp
}

static inline libcouchbase_storage_t
async_cmd_to_storop(PLCBA_cmd_t cmd)
{
    switch(cmd) {
    case PLCBA_CMD_SET:
        return LIBCOUCHBASE_SET;
    case PLCBA_CMD_ADD:
        return LIBCOUCHBASE_ADD;
    case PLCBA_CMD_APPEND:
        return LIBCOUCHBASE_APPEND;
    case PLCBA_CMD_PREPEND:
        return LIBCOUCHBASE_PREPEND;
    case PLCBA_CMD_REPLACE:
        return LIBCOUCHBASE_REPLACE;
    default:
        die("Unknown command");
        return LIBCOUCHBASE_REPLACE; /*make compiler happy*/
    }
}

/*single error for single operation on a cookie*/
static inline void
error_single(
    PLCBA_t *async,
    PLCBA_cookie_t *cookie,
    const char *key, size_t nkey,
    libcouchbase_error_t err)
{
    die("Grrr...");
}

/*single error for multiple operations on a cookie*/
static inline void
error_true_multi(
    PLCBA_t *async,
    PLCBA_cookie_t *cookie,
    size_t num_keys,
    const char **keys, size_t *nkey,
    libcouchbase_error_t err)
{
    int i;
    for(i = 0; i < num_keys; i++) {
        error_single(async, cookie, keys[i], nkey[i], err);
    }
}

/*multiple errors for multiple operations on a cookie*/
static inline void
error_pseudo_multi(
    PLCBA_t *async,
    PLCBA_cookie_t *cookie,
    AV *reqlist,
    libcouchbase_error_t *errors)
{
    int i, idx_max;
    AV *reqav;
    libcouchbase_error_t errtmp;
    SV **tmpsv;
    
    idx_max = av_len(reqlist);
    for(i = 0; i <= idx_max; i++) {
        if(errors[i] == LIBCOUCHBASE_SUCCESS) {
            continue;
        }
        reqav = (AV*)*(av_fetch(reqlist, i, 0));
        tmpsv = av_fetch(reqav, PLCBA_REQIDX_KEY, 0);
        error_single(async, cookie, SvPVX_const(*tmpsv), SvLEN(*tmpsv),
                     errors[i]);
    }
}

void
PLCBA_request(
    SV *self,
    int cmd, int reqtype,
    SV *callcb, SV *cbdata, int cbtype,
    AV *params)
{
    PLCBA_cmd_t cmdtype;
    struct PLCBA_request_st r;
    
    PLCBA_t *async;
    libcouchbase_t instance;
    PLCB_t *base;
    AV *reqav;
    
    PLCBA_cookie_t *cookie;
    int nreq, i;
    libcouchbase_error_t *errors;
    int errcount;
    int has_conversion;
    
    SV **tmpsv;
    
    time_t *multi_exp;
    void **multi_key;
    size_t *multi_nkey;
    
    libcouchbase_error_t err;
    libcouchbase_storage_t storop;
    
    _mk_common_vars(self, instance, base, async);
    
    Newxz(cookie, 1, PLCBA_cookie_t);
    if(SvTYPE(callcb) == SVt_NULL) {
        die("Must have callback for asynchronous request");
    }
    
    if(reqtype == PLCBA_REQTYPE_MULTI) {
        nreq = av_len(params) + 1;
        if(!nreq) {
            die("No requests specified");
        }
    } else {
        nreq = 1;
    }
    
    cookie->callcb = callcb; SvREFCNT_inc(callcb);
    cookie->cbdata = cbdata; SvREFCNT_inc(cbdata);
    cookie->cbtype = cbtype;
    cookie->results = newHV();
    cookie->parent = async;
    cookie->remaining = nreq;
    
    /*pseudo-multi system:
     
     Most commands do not have a libcouchbase-level 'multi' implementation, but
     nevertheless it's more efficient to allow a 'multi' option from Perl because
     sub and xsub overhead is very expensive.
     
     Each operation defines a macro '_do_cbop' which does the following:
        1) call the libcouchbase api function appropriate for that operation
        2) set the function variable 'err' to the error which ocurred.
        
    the predefined pseudo_perform macro does the rest by doing the following:
        1) check to see if the request is multiple or single
        in the case of multiple requests, it:
            I) fetches the current request AV
            II) ensures the request is valid and defined
            III) extracts the information from the request into our request_st
                structure named 'r'
            IV) calls the locally-defined _do_cbop (which sets the error)
            V) checks the current value of 'err', if it is not a success, the
                error counter is incremented
            VI) when the loop has terminated, the error counter is checked again,
                and if it is greater than zero, the error dispatcher is called
        in the case of a single request, it:
            I) treats 'params' as the request AV
            II) passes the AV to av2request,
            III) calls _do_cbop once, and checks for errors
            IV) if there is an erorr, the dispatcher is called     
    */
    
    #define _fetch_assert(idx) \
        if((tmpsv = av_fetch(params, idx, 0)) == NULL) { \
            die("Null request found in request list"); \
        } \
        av2request(async, cmd, (AV*)*tmpsv, &r);
        
    #define pseudo_multi_begin \
        Newxz(errors, nreq, libcouchbase_error_t); \
        errcount = 0;
    #define pseudo_multi_maybe_add \
        if( (errors[i] = err) != LIBCOUCHBASE_SUCCESS ) \
            errcount++;
    #define pseudo_multi_end \
        if(errcount) \
            error_pseudo_multi(async, params, errors, cookie); \
        Safefree(errors);
    
    #define pseudo_perform \
        if(reqtype == PLCBA_REQTYPE_MULTI) { \
            pseudo_multi_begin; \
            for(i = 0; i < nreq; i++) { \
                _fetch_assert(i); \
                _do_cbop(); \
                pseudo_multi_maybe_add; \
            } \
        } else { \
            _do_cbop(); \
            if(err != LIBCOUCHBASE_SUCCESS) { \
                error_single(async, cookie, r.key, r.nkey, err); \
            } \
        } \
    
    switch(cmd) {
        
    case PLCBA_CMD_GET:
    case PLCBA_CMD_TOUCH:
        #define _do_cbop(klist, szlist, explist) \
        if(cmd == PLCBA_CMD_GET) { \
            err = libcouchbase_mget(instance, cookie, nreq, \
                                    (const void* const*)klist, \
                                    (szlist), explist); \
        } else { \
            err = libcouchbase_mtouch(instance, cookie, nreq, \
                                    (const void* const*)klist, \
                                    szlist, explist); \
        }
        
        if(reqtype == PLCBA_REQTYPE_MULTI) {
            Newx(multi_key, nreq, void*);
            Newx(multi_nkey, nreq, size_t);
            Newx(multi_exp, nreq, time_t);
            for(i = 0; i < nreq; i++) {
                _fetch_assert(i);
                multi_key[i] = r.key;
                multi_nkey[i] = r.nkey;
                multi_exp[i] = r.exp;
            }

            _do_cbop(multi_key, multi_nkey, multi_exp);
            if(err != LIBCOUCHBASE_SUCCESS) {
                error_true_multi(
                    async, cookie, nreq, (const char**)multi_key, multi_nkey, err);
            }
            Safefree(multi_key);
            Safefree(multi_nkey);
            Safefree(multi_exp);
        } else {
            av2request(async, cmd, params, &r);
            _do_cbop(&(r.key), &(r.nkey), &(r.exp));
            if(err != LIBCOUCHBASE_SUCCESS) {
                error_single(async, cookie, r.key, r.nkey, err);
            }
        }
        break;
        #undef _do_cbop

    case PLCBA_CMD_SET:
    case PLCBA_CMD_ADD:
    case PLCBA_CMD_REPLACE:
    case PLCBA_CMD_APPEND:
    case PLCBA_CMD_PREPEND:
        storop = async_cmd_to_storop(cmd);
        has_conversion = plcba_cmd_needs_conversion(cmd);
        #define _do_cbop() \
            err = libcouchbase_store(instance, cookie, storop, r.key, r.nkey, \
                                    SvPVX(r.value), r.nvalue, r.store_flags, \
                                    r.exp, r.cas); \
            if(has_conversion) { \
                plcb_convert_storage_free(base, r.value, r.store_flags); \
            }
        
        pseudo_perform;
        break;
        #undef _do_cbop
    
    case PLCBA_CMD_ARITHMETIC:
        #define _do_cbop() \
            err = libcouchbase_arithmetic(instance, cookie, r.key, r.nkey, \
                                r.arithmetic.delta, r.exp, \
                                r.arithmetic.create, r.arithmetic.initial);
        pseudo_perform;
        break;
        #undef _do_cbop
    case PLCBA_CMD_REMOVE:
        #define _do_cbop() \
            err = libcouchbase_remove(instance, cookie, r.key, r.nkey, r.cas);
        pseudo_perform;
        break;
        #undef _do_cbop

    default:
        die("Unimplemented!");
    }
    
    #undef _fetch_assert
    #undef pseudo_multi_begin
    #undef pseduo_multi_maybe_add
    #undef pseudo_multi_end
    #undef pseudo_perform
}


static inline void
extract_async_options(PLCBA_t *async, AV *options)
{
    SV **tmpsv;
    if( (tmpsv = av_fetch(options, PLCBA_CTORIDX_CBEVMOD, 0)) == NULL) {
        die("Must have update event callback");
    }
    SvREFCNT_inc(*tmpsv);
    async->cv_evmod = *tmpsv;
    
    if( (tmpsv = av_fetch(options, PLCBA_CTORIDX_CBERR, 0)) == NULL) {
        die("Must have error event callback");
    }
    async->cv_err = *tmpsv;
    SvREFCNT_inc(*tmpsv);
    
}

SV *PLCBA_construct(const char *pkg, AV *options)
{
    PLCBA_t *async;
    plcba_cbcio *cbcio;
    char *host, *username, *password, *bucket;
    libcouchbase_t instance;
    SV *blessed_obj;
    
    Newxz(async, 1, PLCBA_t);
    
    extract_async_options(async, options);
    
    plcb_ctor_conversion_opts(&async->base, options);
    
    cbcio = plcba_default_io_opts();
    
    cbcio->cookie = async;
    
    cbcio->create_event = create_event;
    cbcio->destroy_event = destroy_event;
    cbcio->update_event = update_event;
    cbcio->delete_event = delete_event;
    cbcio->run_event_loop = run_event_loop;
    cbcio->stop_event_loop = stop_event_loop;
    
    plcb_ctor_cbc_opts(options, &host, &username, &password, &bucket);
    instance = libcouchbase_create(host, username, password, bucket, cbcio);
    
    if(!instance) {
        die("Couldn't create instance!");
    }
    
    plcb_ctor_init_common(&async->base, instance);
    plcba_setup_callbacks(async);
    
    blessed_obj = newSV(0);
    sv_setiv(newSVrv(blessed_obj, pkg), PTR2IV(async));
    return blessed_obj;
}

/*called from perl when an event arrives*/
void
PLCBA_HaveEvent(const char *pkg, short flags, SV *opaque)
{
    /*TODO: optmize this to take an arrayref, and maybe configure ourselves for
     event loops which have a different calling convention, e.g. POE*/
    
    PLCBA_c_event *cevent;
    warn("Flags are %d, opaque is %p", flags, opaque);
    //sv_dump(opaque);
    
    cevent = NUM2PTR(PLCBA_c_event*, SvIV(opaque));
    cevent->c.handler(cevent->fd, flags, cevent->c.arg);
}

void
PLCBA_connect(SV *self)
{
    libcouchbase_t instance;
    PLCBA_t *async;
    PLCB_t *base;
    _mk_common_vars(self, instance, base, async);
    warn("Connecting...");
    libcouchbase_connect(instance);
}
