#include "perl-couchbase.h"

void
plcb_schedctx_init_common(PLCB_t *obj, PLCB_args_t *args,
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
        SAVEFREESV(sync->u.multiret);
    } else {
        sync->u.ret = (AV*)SvRV(args->keys);
        sync->type = PLCB_SYNCTYPE_SINGLE;
        sync->flags = PLCB_SYNCf_SINGLERET;
    }
    ctx->cookie = sync;
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
        ret = ctx->obj;
        SvREFCNT_inc(ctx->obj);
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
        if (!plcb_ret_isa(ctx->parent, ctx->obj)) {
            die("Object must be a %s", PLCB_RET_CLASSNAME);
        }
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
argiter_fail_common(PLCB_schedctx_t *ctx, const char *key, lcb_SIZE nkey,
    SV *docsv, SV *options)
{
    plcb_ret_set_err(ctx->parent, (AV*)SvRV(docsv), ctx->err);
    (void)key; (void)nkey; (void)docsv; (void)options;
}

static void
key_from_ret(SV *retobj, const char **key, lcb_SIZE *nkey)
{
    AV *ret = (AV*)SvRV(retobj);
    SV **tmpsv = av_fetch(ret, PLCB_RETIDX_KEY, 0);
    if (!tmpsv) {
        die("Cannot pass document without key");
    }

    plcb_get_str_or_die(*tmpsv, *key, *nkey, "Invalid key");
}

static int
handle_current_item(PLCB_schedctx_t *ctx, SV *elem, plcb_iter_cb callback)
{
    SV *docsv;
    SV *optsv = NULL;
    const char *key;
    size_t nkey;

    /* Can either be in the format of => $doc, or => [ $doc, $options ] */
    if (plcb_ret_isa(ctx->parent, elem)) {
        docsv = elem;

    } else if (SvROK(elem) && SvTYPE(SvRV(elem)) == SVt_PVAV) {
        /* Is an array */
        AV *tuple = (AV*)SvRV(elem);
        int arrlen = av_len(tuple) + 1;
        if (arrlen > 2) {
            die("Tuple element must be an array of two elements");
        } else if (arrlen < 1) {
            warn("Found empty element");
            return 0;
        }

        docsv = *av_fetch(tuple, 0, 0);
        if (!plcb_ret_isa(ctx->parent, docsv)) {
            die("Expected %s", PLCB_RET_CLASSNAME);
        }

        if (arrlen == 2) {
            optsv = *av_fetch(tuple, 1, 0);
        }

    } else {
        die("Element must be a %s or an array of [ $doc, $options ]", PLCB_RET_CLASSNAME);
    }

    key_from_ret(docsv, &key, &nkey);
    hv_store(ctx->sync->u.multiret, key, nkey, docsv, 0);
    SvREFCNT_inc(docsv);
    callback(ctx, key, nkey, docsv, optsv);
    return 1;
}

static void
iter_run(PLCB_schedctx_t* ctx, plcb_iter_cb callback)
{
    ctx->loop = 1;
    if (ctx->flags & PLCB_ARGITERf_SINGLE) {
        const char *key;
        size_t nkey;

        key_from_ret(ctx->obj, &key, &nkey);
        callback(ctx, key, nkey, ctx->obj, NULL);
        ctx->nreq = 1;
        return;
    }

    if (SvTYPE(ctx->obj) == SVt_PVAV) {
        AV *av = (AV *)ctx->obj;
        int ii;
        int maxix = av_len(av)+1;

        for (ii = 0; ii < maxix && LOOP_OK(ctx); ii++) {
            SV *cur = *av_fetch(av, ii, 0);
            ctx->nreq += handle_current_item(ctx, cur, callback);
        }
    } else {
        HV *hv = (HV *)ctx->obj;
        HE *ent;
        hv_iterinit(hv);

        while ((ent = hv_iternext(hv))) {
            SV *cur = hv_iterval(hv, ent);
            ctx->nreq += handle_current_item(ctx, cur, callback);
        }
    }
}


void
plcb_schedctx_iter_bail(PLCB_schedctx_t *ctx, lcb_error_t err)
{
    iter_run(ctx, argiter_fail_common);
}

void
plcb_schedctx_iter_run(PLCB_schedctx_t *ctx, plcb_iter_cb callback)
{
    iter_run(ctx, callback);
}
