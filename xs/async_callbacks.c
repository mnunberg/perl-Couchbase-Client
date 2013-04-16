#include "perl-couchbase-async.h"

#define _R \
    resp->v.v0

static void tell_perl(PLCBA_cookie_t *cookie,
                      AV *ret,
                      const char *key,
                      size_t nkey)
{
    dSP;
    
    (void) hv_store(cookie->results,
            key,
            nkey,
            plcb_ret_blessed_rv(&(cookie->parent->base), ret),
            0);
    
    cookie->remaining--;    
    
    if (cookie->cbtype == PLCBA_CBTYPE_INCREMENTAL ||
       (cookie->cbtype == PLCBA_CBTYPE_COMPLETION &&
        cookie->remaining == 0)) {
        
        ENTER;
        SAVETMPS;
        PUSHMARK(SP);
        
        XPUSHs(sv_2mortal(newRV_inc((SV*)cookie->results)));
        XPUSHs(cookie->cbdata);
        
        PUTBACK;
        
        call_sv(cookie->callcb, G_DISCARD);
        
        FREETMPS;
        LEAVE;
    }
    
    if (!cookie->remaining) {
        SvREFCNT_dec(cookie->results);
        SvREFCNT_dec(cookie->callcb);
        SvREFCNT_dec(cookie->cbdata);
        Safefree(cookie);
    }
}

void plcba_callback_notify_err(PLCBA_t *async,
                               PLCBA_cookie_t *cookie,
                               const char *key,
                               size_t nkey,
                               lcb_error_t err)
{
    AV *ret;
    
    warn("Got immediate error for %s", key);
    ret = newAV();
    plcb_ret_set_err((&(async->base)), ret, err);
    tell_perl(cookie, ret, key, nkey);
}

/*macro to define common variables and operations for callbacks*/

#define _CB_INIT \
    PLCBA_cookie_t *cookie; \
    AV *ret; \
    PLCB_t *object; \
    \
    ret = newAV(); \
    cookie = (PLCBA_cookie_t*)(v_cookie); \
    object = &(cookie->parent->base); \
    plcb_ret_set_err(object, ret, err);

static void get_callback(lcb_t instance,
                         const void *v_cookie,
                         lcb_error_t err,
                         const lcb_get_resp_t *resp)
{
    _CB_INIT;
    //warn("Get callback");
    if (err == LIBCOUCHBASE_SUCCESS) {
        //warn("Got value of %d bytes", nbytes);
        plcb_ret_set_strval(object, ret, _R.bytes, _R.nbytes, _R.flags, _R.cas);
    }
    tell_perl(cookie, ret, _R.key, _R.nkey);
}

static void storage_callback(lcb_t instance,
                             const void *v_cookie,
                             lcb_storage_t operation,
                             lcb_error_t err,
                             const lcb_store_resp_t *resp)
{
    _CB_INIT;
    if (_R.cas) {
        plcb_ret_set_cas(object, ret, &_R.cas);
    }

    tell_perl(cookie, ret, _R.key, _R.nkey);
}

static void arithmetic_callback(lcb_t instance,
                                const void *v_cookie,
                                lcb_error_t err,
                                const lcb_arithmetic_resp_t *resp)
{
    _CB_INIT;
    if (err == LIBCOUCHBASE_SUCCESS) {
        plcb_ret_set_numval(object, ret, _R.value, _R.cas);
    }
    tell_perl(cookie, ret, _R.key, _R.nkey);
}

static void remove_callback(lcb_t instance,
                            const void *v_cookie,
                            lcb_error_t err,
                            const lcb_remove_resp_t *resp)
{
    _CB_INIT;
    plcb_ret_set_cas(object, ret, &_R.cas);
    tell_perl(cookie, ret, _R.key, _R.nkey);
}

/*stat not implemented*/

static void touch_callback(lcb_t instance,
                           const void *v_cookie,
                           lcb_error_t err,
                           const lcb_touch_resp_t *resp)
{
    _CB_INIT;
    plcb_ret_set_cas(object, ret, &_R.cas);
    tell_perl(cookie, ret, _R.key, _R.nkey);
}

static void error_callback(lcb_t instance, lcb_error_t err, const char *errinfo)
{
    PLCBA_t *async;
    dSP;

    async = (PLCBA_t*)lcb_get_cookie(instance);
    ENTER;
    SAVETMPS;
    PUSHMARK(SP);
    
    XPUSHs(sv_2mortal(newSViv(err)));
    XPUSHs(sv_2mortal(newSVpv(errinfo, 0)));
    PUTBACK;
    
    call_sv(async->cv_err, G_DISCARD);
    
    FREETMPS;
    LEAVE;
}

void plcba_setup_callbacks(PLCBA_t *async)
{
    lcb_t instance;
    
    instance = async->base.instance;
    
    lcb_set_get_callback(instance, get_callback);
    lcb_set_store_callback(instance, storage_callback);
    lcb_set_arithmetic_callback(instance, arithmetic_callback);
    lcb_set_remove_callback(instance, remove_callback);
    /*
    lcb_set_stats_callback(instance, stats_callback);
    */
    lcb_set_touch_callback(instance, touch_callback);
    lcb_set_error_callback(instance, error_callback);
    
    lcb_set_cookie(instance, async);
}
