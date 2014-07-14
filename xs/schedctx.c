#include "perl-couchbase.h"

void
plcb_schedctx_init_common(PLCB_t *obj, SV *self, PLCB_args_t *args,
    PLCB_sync_t *sync, PLCB_schedctx_t *ctx)
{
    /* assume ctx is zeroed */
    ctx->parent = obj;
    ctx->args = args;
    ctx->cmdbase = args->cmd & PLCB_COMMAND_MASK;

    if (sync) {
        ctx->sync = sync;
    } else {
        ctx->sync = &obj->sync;
        sync = ctx->sync;
        sync->parent = obj;
    }

    if (args->cmd & PLCB_COMMANDf_MULTI) {
        sync->u.multiret = newHV();
        sync->type = PLCB_SYNCTYPE_MULTI;
        sync->flags = PLCB_SYNCf_MULTIRET;
    } else {

        sync->u.ret = newAV();
        sync->type = PLCB_SYNCTYPE_SINGLE;
        sync->flags = PLCB_SYNCf_SINGLERET;
    }
    ctx->cookie = sync;
    SAVEFREESV(sync->u.ret);
    SAVEDESTRUCTOR(lcb_sched_fail, obj->instance);
    lcb_sched_enter(obj->instance);
}

SV *
plcb_schedctx_return(PLCB_schedctx_t *ctx)
{
    PLCB_sync_t *sync = ctx->sync;
    SV *ret;

    if (ctx->err == LCB_SUCCESS) {
        ctx->parent->npending += ctx->nreq;
        sync->remaining = ctx->nreq;
        lcb_sched_leave(ctx->parent->instance);
        lcb_wait3(ctx->parent->instance, LCB_WAIT_NOCHECK);
    }

    if (sync->type == PLCB_SYNCTYPE_SINGLE) {
        SvREFCNT_inc((SV*)sync->u.ret);
        ret = plcb_ret_blessed_rv(ctx->parent, sync->u.ret);
    } else {
        SvREFCNT_inc((SV*)sync->u.multiret);
        ret = newRV_noinc((SV*)sync->u.multiret);
    }
    return ret;
}

void
plcb_schedctx_iter_start(PLCB_schedctx_t *ctx)
{
    SV *keys;
    if (ctx->args->cmd & PLCB_COMMANDf_SINGLE) {
        ctx->obj = ctx->args->keys;
        ctx->flags |= PLCB_ARGITERf_SINGLE;
        return;
    }

    /* Multi Commands */
    keys = ctx->args->keys;
    if (SvROK(keys)) {
        keys = SvRV(keys);
    }

    ctx->obj = keys;
    if (SvTYPE(keys) != SVt_PVAV && SvTYPE(keys) != SVt_PVHV) {
        die("Keys must be a HASH or ARRAY reference");
    }

    if (SvTYPE(keys) == SVt_PVAV && (PLCB_ARGITERf_RAWKEY_OK) == 0) {
        die("Keys must be a HASH reference");
    }

    ctx->loop = 1;
}

#define LOOP_OK(ctx) (ctx)->loop == 1


static void
argiter_fail_common(PLCB_schedctx_t *ctx, const char *key, lcb_SIZE nkey, SV *options)
{
    PLCB_sync_t *sync = ctx->sync;

    if (sync->type == PLCB_SYNCTYPE_SINGLE) {
        plcb_ret_set_err(ctx->parent, sync->u.ret, ctx->err);
    } else {
        SV *cursv, *blessed;
        AV *errav;
        cursv = *hv_fetch(sync->u.multiret, key, nkey, 1);
        if (!SvOK(cursv)) {
            errav = newAV();
            blessed = plcb_ret_blessed_rv(ctx->parent, errav);
            SvSetSV(blessed, cursv);
        } else {
            errav = (AV*)SvRV(cursv);
        }

        plcb_ret_set_err(ctx->parent, errav, ctx->err);
    }
}

static void
preinsert_key(PLCB_schedctx_t *ctx, const char *key, lcb_SIZE nkey)
{
    AV *retval;
    SV *blessed;
    PLCB_sync_t *sync = ctx->sync;
    if (sync->flags & PLCB_SYNCf_SINGLERET) {
        return;
    }
    retval = newAV();
    blessed = plcb_ret_blessed_rv(ctx->parent, retval);
    hv_store(sync->u.multiret, key, nkey, blessed, 0);
}


static void
iter_run(PLCB_schedctx_t* ctx, plcb_iter_cb callback, int preinsert)
{
    int ii;
    const char *key;
    lcb_SIZE nkey;

    ctx->loop = 1;

    if (ctx->flags & PLCB_ARGITERf_SINGLE) {
        plcb_get_str_or_die(ctx->obj, key, nkey, "Invalid key");
        callback(ctx, key, nkey, NULL);
        ctx->nreq = 1;
        return;
    }

    if (SvTYPE(ctx->obj) == SVt_PVAV) {
        AV *av = (AV *)ctx->obj;
        int maxix = av_len(av)+1;

        for (ii = 0; ii < maxix && LOOP_OK(ctx); ii++) {
            SV *cursv = *av_fetch(av, ii, 0);
            SV *valsv = NULL;

            if (SvROK(cursv)) {
                /* It's a sub-options type! */
                valsv = SvRV(cursv);

                if (SvTYPE(valsv) == SVt_PVAV) {
                    if (av_len((AV*)valsv) == -1) {
                        die("Empty array passed in list");
                    }
                } else if (SvTYPE(valsv) == SVt_PVHV) {
                    /* Find the key! */
                    SV **tmpsv = hv_fetchs((HV*)valsv, "key", 0);
                    if (!tmpsv) {
                        die("Found hashref without key as element");
                    }
                } else {
                    die("Unhandled reference type passed as element");
                }
            }

            plcb_get_str_or_die(cursv, key, nkey, "Expected key as element");
            if (preinsert) {
                preinsert_key(ctx, key, nkey);
            }
            callback(ctx, key, nkey, NULL);
        }
    } else {
        ii = 0;
        HV *hv = (HV *)ctx->obj;
        SV *curval;
        I32 curlen;
        hv_iterinit(hv);
        while ((curval = hv_iternextsv(hv, (char**)&key, &curlen)) && LOOP_OK(ctx)) {
            if (preinsert) {
                preinsert_key(ctx, key, curlen);
            }
            callback(ctx, key, curlen, curval);
            ii++;
        }
    }
    ctx->nreq = ii;
}


void
plcb_schedctx_iter_bail(PLCB_schedctx_t *ctx, lcb_error_t err)
{
    iter_run(ctx, argiter_fail_common, 0);
}

void
plcb_schedctx_iter_run(PLCB_schedctx_t *ctx, plcb_iter_cb callback)
{
    iter_run(ctx, callback, 1);
}
