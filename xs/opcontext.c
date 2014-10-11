#include "perl-couchbase.h"
SV *
plcb_opctx_new(PLCB_t *parent, int flags)
{
    plcb_OPCTX *ctx;
    Newxz(ctx, 1, plcb_OPCTX);

    SV *blessed = newSV(0);
    sv_setiv(blessed, PTR2IV(ctx));
    blessed = newRV_noinc(blessed);
    sv_bless(blessed, parent->opctx_sync_stash);

    ctx->flags = flags;
    ctx->parent = newRV_inc(parent->selfobj);
    sv_rvweaken(ctx->parent);

    return blessed;
}

void
plcb_opctx_clear(PLCB_t *parent)
{
    if (!parent->curctx) {
        return;
    }
    SvREFCNT_dec(parent->curctx);
    parent->curctx = NULL;
}

void
plcb_opctx_initop(plcb_SINGLEOP *so, PLCB_t *parent, SV *doc, SV *ctx, SV *options)
{
    if (!plcb_doc_isa(parent, doc)) {
        sv_dump(doc);
        die("Must pass a " PLCB_RET_CLASSNAME);
        /* Initialize the document to 0 */
    }
    so->docrv = doc;
    so->docav = (AV *)SvRV(doc);
    so->opctx = ctx;
    so->parent = parent;
    so->cookie = so->docav;

    plcb_doc_set_err(parent, so->docav, -1);

    if (options && SvTYPE(options) != SVt_NULL) {
        if (SvROK(options) == 0 || SvTYPE(SvRV(options)) != SVt_PVHV) {
            sv_dump(options);
            die("options must be undef or a HASH reference");
        }
        so->cmdopts = options;
    }

    if (ctx && SvTYPE(ctx) != SVt_NULL) {
        if (!plcb_opctx_isa(parent, ctx)) {
            die("ctx must be undef or a %s object", PLCB_OPCTX_CLASSNAME);
        }
        if (parent->curctx && SvRV(ctx) != SvRV(parent->curctx)) {
            sv_dump(parent->curctx);
            sv_dump(ctx);
            die("Current context already set!");
        }
        so->opctx = ctx;
    } else {
        if (parent->curctx && SvRV(parent->curctx) != SvRV(ctx)) {
            plcb_OPCTX *oldctx = NUM2PTR(plcb_OPCTX*, SvIVX(SvRV(parent->curctx)));
            if (oldctx->nremaining) {
                warn("Existing batch context found. This may leak memory. Have %d items remaining", oldctx->nremaining);
            }
            lcb_sched_fail(parent->instance);
            plcb_opctx_clear(parent);
        }

        assert(parent->curctx == NULL);

        if (parent->async) {
            so->opctx = plcb_opctx_new(parent, PLCB_OPCTXf_IMPLICIT);
            /* If we get an error, don't leave the pointer dangling */
            SAVEFREESV(so->opctx);

        } else {
            so->opctx = parent->deflctx;
        }
        lcb_sched_enter(parent->instance);
    }
}

SV *
plcb_opctx_return(plcb_SINGLEOP *so, lcb_error_t err)
{
    /* Figure out what type of context we are */
    int haserr = 0;
    SV *retval;
    plcb_OPCTX *ctx = NUM2PTR(plcb_OPCTX*, SvIV(SvRV(so->opctx)));

    if (err != LCB_SUCCESS) {
        /* Remove the doc's "Parent" field */
        av_store(so->docav, PLCB_RETIDX_PARENT, &PL_sv_undef);

        if (ctx->flags & PLCB_OPCTXf_IMPLICIT) {
            if (so->parent)
            lcb_sched_fail(so->parent->instance);
        }

        warn("Couldn't schedule operation. Code 0x%x (%s)\n", err, lcb_strerror(NULL, err));
        plcb_doc_set_err(so->parent, so->docav, err);
        haserr = 1;
        goto GT_RET;
    }

    /* Increment refcount for the parent */
    av_store(so->docav, PLCB_RETIDX_PARENT, newRV_inc(SvRV(so->opctx)));
    /* Increment refcount for the doc itself (decremented in callback) */
    SvREFCNT_inc((SV*)so->docav);
    /* Increment remaining count on the context */
    ctx->nremaining++;

    if (ctx->flags & PLCB_OPCTXf_IMPLICIT) {
        if (so->parent->async) {
            SvREFCNT_inc(so->opctx); /* Undo SAVEFREESV */
        }

        lcb_sched_leave(so->parent->instance);

        if (so->parent->async) {
            goto GT_RET;
        }

        lcb_wait3(so->parent->instance, LCB_WAIT_NOCHECK);
        /* See if we have an error */
        if (plcb_doc_get_err(so->docav) != LCB_SUCCESS) {
            haserr = 1;
        }
    }

    GT_RET:
    if (ctx->flags & PLCB_OPCTXf_IMPLICIT) {
        if (haserr) {
            retval = &PL_sv_no;
        } else if (so->parent->async) {
            retval = so->opctx;
            SvREFCNT_inc(so->opctx);
        } else {
            retval = &PL_sv_yes;
        }
    } else {
        retval = so->opctx;
        SvREFCNT_inc(so->opctx);
    }

    SvREFCNT_inc(retval);
    return retval;
}
