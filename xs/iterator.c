#include "perl-couchbase.h"

void
plcb_multi_iterator_collect(PLCB_iter_t *iter,
                            lcb_error_t err,
                            const void *key, size_t nkey,
                            const void *value, size_t nvalue,
                            uint32_t flags, uint64_t cas)
{
    SV *blessed_rv, *ksv;
    AV *cur_ret;

    /* If the object has been destroyed in perl, then just warn and maybe free */
    if (iter->pl_destroyed) {
        warn("Received data for destroyed iterator. You are hurting your network");
        iter->remaining--;
        if (iter->remaining == 0) {
            if (iter->pl_destroyed) {
                Safefree(iter);
            }
        }
        return;
    }

    cur_ret = newAV();
    blessed_rv = newRV_noinc((SV*)cur_ret);
    sv_bless(blessed_rv, iter->parent->ret_stash);

    /* Simply set the return value, and stop the event loop */
    plcb_ret_set_err(iter->parent, cur_ret, err);
    if (err == LIBCOUCHBASE_SUCCESS) {
        plcb_ret_set_strval(iter->parent, cur_ret, value, nvalue, flags, cas);
    }

    ksv = newSVpvn(key, nkey);

    av_push(iter->buffer_av, ksv);
    av_push(iter->buffer_av, blessed_rv);

    iter->remaining--;
}

static void iter_get_callback(lcb_t instance,
                              const void *cookie,
                              lcb_error_t err,
                              const lcb_get_resp_t *resp)
{
    PLCB_iter_t *iter = (PLCB_iter_t*)cookie;
    plcb_multi_iterator_collect(iter, err,
                                resp->v.v0.key,
                                resp->v.v0.nkey,
                                resp->v.v0.bytes,
                                resp->v.v0.nbytes,
                                resp->v.v0.flags,
                                resp->v.v0.cas);

    /* This is the stopping version */
    plcb_evloop_stop(iter->parent);
}

/**
 * Create a new iterator object. This wraps around lcb_mget
 */
SV*
plcb_multi_iterator_new(PLCB_t *obj, SV *cbo_sv,
                        const void * const *keys, size_t *sizes, time_t *exps,
                        size_t nitems)
{
    SV *my_iv, *ret_rv;
    PLCB_iter_t *iterobj;
    lcb_error_t err;

    Newxz(iterobj, 1, PLCB_iter_t);
    iterobj->parent_rv = newRV_inc(SvRV(cbo_sv));
    iterobj->parent = obj;
    iterobj->type = PLCB_SYNCTYPE_ITER;
    iterobj->buffer_av = newAV();
    iterobj->error_av = NULL;

    my_iv = newSViv(PTR2IV(iterobj));
    ret_rv = newRV_noinc(my_iv);

    sv_bless(ret_rv, obj->iter_stash);

    err = libcouchbase_mget(obj->instance, iterobj, nitems, keys, sizes, exps);

    if (err != LIBCOUCHBASE_SUCCESS) {
        SV *tmprv;
        iterobj->error_av = newAV();
        tmprv = newRV_inc((SV*)iterobj->error_av);
        sv_bless(tmprv, obj->ret_stash);
        SvREFCNT_dec(tmprv);
        plcb_ret_set_err(obj, iterobj->error_av, err);
        iterobj->remaining = PLCB_ITER_ERROR;
    } else {
        iterobj->remaining = nitems;
    }
    return ret_rv;
}

/**
 * Perform a single step on an iterator object.
 * Populates the keyp and retp pointers with a string key,
 * and a Couchbase::Client::Return object.
 */
void
plcb_multi_iterator_next(PLCB_iter_t *iter, SV **keyp, SV **retp)
{
    SV *retrv;
    lcb_get_callback old_callback;
    int old_remaining;
    int return_final;

    *keyp = NULL;
    *retp = NULL;

    if (iter->remaining == PLCB_ITER_ERROR) {
        /* Error */
        return;
    }

    GT_FETCHONE:
    if (av_len(iter->buffer_av) > 0) {
        *retp = av_pop(iter->buffer_av);
        *keyp = av_pop(iter->buffer_av);
        return;
    } else {
        if (iter->remaining == 0) {
            /* Nothing left, and nothing in the buffer */
            return;
        }
    }

    /* Install the single callback */
    old_callback = lcb_set_get_callback(iter->parent->instance,
            iter_get_callback);

    plcb_evloop_start(iter->parent);

    /* Restore the old callback */
    lcb_set_get_callback(iter->parent->instance, old_callback);

    goto GT_FETCHONE;
}


/**
 * Called normally from a DESTROY method.
 */
void
plcb_multi_iterator_cleanup(PLCB_iter_t *iter)
{
    assert(iter->pl_destroyed == 0);

    iter->pl_destroyed = 1;

    SvREFCNT_dec(iter->parent_rv);
    iter->parent_rv = NULL;

    SvREFCNT_dec(iter->buffer_av);
    iter->buffer_av = NULL;

    if (iter->error_av) {
        SvREFCNT_dec(iter->error_av);
        iter->error_av = NULL;
    }

    if (iter->remaining > 0) {
        return;
    }

    Safefree(iter);
}
