#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "perl-couchbase.h"

#define _R \
    resp->v.v0

void plcb_evloop_wait_unref(PLCB_t *object)
{
    assert(object->npending);
    object->npending--;
    if (!object->npending) {
        plcb_evloop_stop(object);
    }
}

static void single_keyop_common(lcb_t instance,
                                const void *cookie,
                                lcb_error_t err,
                                const void *key,
                                size_t nkey,
                                const void *bytes,
                                size_t nbytes,
                                uint32_t flags,
                                uint64_t cas)
{
    PLCB_sync_t *syncp = plcb_sync_cast(cookie);

    if (syncp->type != PLCB_SYNCTYPE_SINGLE) {
        plcb_multi_iterator_collect((PLCB_iter_t*) cookie,
                                    err,
                                    key,
                                    nkey,
                                    bytes,
                                    nbytes,
                                    flags,
                                    cas);
        return;
    }

    plcb_ret_set_err(syncp->parent, syncp->ret, err);

    if (err == LCB_SUCCESS && bytes) {
        plcb_ret_set_strval( syncp->parent,
                            syncp->ret,
                            bytes,
                            nbytes,
                            flags,
                            cas);
    }

    plcb_evloop_wait_unref(syncp->parent);
}

static void multi_keyop_common(lcb_t instance,
                               const void *cookie,
                               lcb_error_t err,
                               const void *key,
                               size_t nkey,
                               const void *bytes,
                               size_t nbytes,
                               uint32_t flags,
                               uint64_t cas)
{
    PLCB_sync_t *syncp = plcb_sync_cast(cookie);
    AV *ret;
    HV *results;

    plcb_evloop_wait_unref(syncp->parent);

    if (syncp->type != PLCB_SYNCTYPE_SINGLE) {

        plcb_multi_iterator_collect((PLCB_iter_t*) cookie,
                                    err,
                                    key,
                                    nkey,
                                    bytes,
                                    nbytes,
                                    flags,
                                    cas);
        return;
    }

    ret = newAV();
    results = (HV*)(syncp->ret);
    
    (void) hv_store(results,
            key,
            nkey,
            plcb_ret_blessed_rv(syncp->parent, ret),
            0);
    
    plcb_ret_set_err(syncp->parent, ret, err);
    
    if (err == LCB_SUCCESS && nbytes) {
        plcb_ret_set_strval(
            syncp->parent, ret, bytes, nbytes, flags, cas);
    }
}


/**
 * Bleh, new API means more code duplication and boilerplate.
 */
static void cb_get(lcb_t instance,
                   const void *cookie,
                   lcb_error_t error,
                   const lcb_get_resp_t *resp)
{
    single_keyop_common(instance,
                        cookie,
                        error,
                        _R.key,
                        _R.nkey,
                        _R.bytes,
                        _R.nbytes,
                        _R.flags,
                        _R.cas);
}

static void cb_get_multi(lcb_t instance,
                         const void *cookie,
                         lcb_error_t error,
                         const lcb_get_resp_t *resp)
{
    multi_keyop_common(instance,
                       cookie,
                       error,
                       _R.key,
                       _R.nkey,
                       _R.bytes,
                       _R.nbytes,
                       _R.flags,
                       _R.cas);
}

static void cb_touch(lcb_t instance,
                     const void *cookie,
                     lcb_error_t error,
                     const lcb_touch_resp_t *resp)
{
    single_keyop_common(instance,
                        cookie,
                        error,
                        _R.key,
                        _R.nkey,
                        NULL,
                        0,
                        0,
                        _R.cas);
}

static void cb_touch_multi(lcb_t instance,
                           const void *cookie,
                           lcb_error_t error,
                           const lcb_touch_resp_t *resp)
{
    multi_keyop_common(instance,
                       cookie,
                       error,
                       _R.key,
                       _R.nkey,
                       NULL,
                       0,
                       0,
                       _R.cas);
}

static void cb_unlock(lcb_t instance,
                      const void *cookie,
                      lcb_error_t error,
                      const lcb_unlock_resp_t *resp)
{
    single_keyop_common(instance,
                        cookie,
                        error,
                        _R.key,
                        _R.nkey,
                        NULL,
                        0,
                        0,
                        0);
}

static void cb_remove(lcb_t instance,
                      const void *cookie,
                      lcb_error_t error,
                      const lcb_remove_resp_t *resp)
{
    single_keyop_common(instance,
                        cookie,
                        error,
                        _R.key,
                        _R.nkey,
                        NULL,
                        0,
                        0,
                        _R.cas);
}

static void cb_storage(lcb_t instance,
                       const void *cookie,
                       lcb_storage_t op,
                       lcb_error_t err,
                       const lcb_store_resp_t *resp)
{
    PLCB_sync_t *syncp = plcb_sync_cast(cookie);
    plcb_ret_set_err(syncp->parent, syncp->ret, err);

    if (err == LCB_SUCCESS) {
        plcb_ret_set_cas(syncp->parent, syncp->ret, &(_R.cas));
    }

    plcb_evloop_wait_unref(syncp->parent);
}

static void cb_arithmetic(lcb_t instance,
                          const void *cookie,
                          lcb_error_t err,
                          const lcb_arithmetic_resp_t *resp)
{
    PLCB_sync_t *syncp = plcb_sync_cast(cookie);
    plcb_ret_set_err(syncp->parent, syncp->ret, err);

    if (err == LCB_SUCCESS) {
        plcb_ret_set_numval(syncp->parent,
                            syncp->ret,
                            _R.value,
                            _R.cas);
    }

    plcb_evloop_wait_unref(syncp->parent);
}


static void cb_error(lcb_t instance, lcb_error_t err, const char *errinfo)
{
    PLCB_t *object;
    object = (PLCB_t*) lcb_get_cookie(instance);
    plcb_errstack_push(object, err, errinfo);
}

static void cb_observe(lcb_t instance,
                       const void *cookie,
                       lcb_error_t error,
                       const lcb_observe_resp_t *resp)
{
    PLCB_obs_t *obs = (PLCB_obs_t*)cookie;
    printf("Hi!\n");
    
    if (resp->v.v0.key == NULL) {
        plcb_evloop_wait_unref(obs->sync.parent);
        return;
    }
    
    plcb_observe_result(obs, resp);
}

static void cb_stat(lcb_t instance,
                    const void *cookie,
                    lcb_error_t err,
                    const lcb_server_stat_resp_t *resp)
{
    PLCB_t *object;
    SV *server_sv, *data_sv, *key_sv;
    dSP;
    
    object = (PLCB_t*)lcb_get_cookie(instance);
    
    if (_R.key == NULL && _R.server_endpoint == NULL) {
        plcb_evloop_wait_unref(object);
        return;
    }
    
    server_sv = newSVpvn(_R.server_endpoint, strlen(_R.server_endpoint));
    if (_R.nkey) {
        key_sv = newSVpvn(_R.key, _R.nkey);

    } else {
        key_sv = newSVpvn("", 0);
    }
    
    if (_R.nbytes) {
        data_sv = newSVpvn(_R.bytes, _R.nbytes);

    } else {
        data_sv = newSVpvn("", 0);
    }
    
    if (!object->stats_hv) {
        die("We have nothing to write our stats to!");
    }
    
    ENTER;
    SAVETMPS;
    
    PUSHMARK(SP);
    XPUSHs(sv_2mortal(newRV_inc((SV*)object->stats_hv)));
    XPUSHs(sv_2mortal(server_sv));
    XPUSHs(sv_2mortal(key_sv));
    XPUSHs(sv_2mortal(data_sv));
    PUTBACK;
    
    call_pv(PLCB_STATS_SUBNAME, G_DISCARD);
    FREETMPS;
    LEAVE;
}

void plcb_callbacks_set_multi(PLCB_t *object)
{
    lcb_t instance = object->instance;
    lcb_set_get_callback(instance, cb_get_multi);
    lcb_set_touch_callback(instance, cb_touch_multi);
}

void plcb_callbacks_set_single(PLCB_t *object)
{
    lcb_t instance = object->instance;
    lcb_set_get_callback(instance, cb_get);
    lcb_set_touch_callback(instance, cb_touch);
}

void plcb_callbacks_setup(PLCB_t *object)
{
    lcb_t instance = object->instance;
    lcb_set_get_callback(instance, cb_get);
    lcb_set_store_callback(instance, cb_storage);
    lcb_set_error_callback(instance, cb_error);
    lcb_set_touch_callback(instance, cb_touch);
    lcb_set_remove_callback(instance, cb_remove);
    lcb_set_arithmetic_callback(instance, cb_arithmetic);
    lcb_set_stat_callback(instance, cb_stat);
    lcb_set_observe_callback(instance, cb_observe);
    lcb_set_unlock_callback(instance, cb_unlock);
    
    lcb_set_cookie(instance, object);
}
