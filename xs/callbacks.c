#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "perl-couchbase.h"

void plcb_evloop_wait_unref(PLCB_t *obj) { (void)obj; }

static int
chain_endure(PLCB_t *obj, AV *resobj, const lcb_RESPSTORE *resp)
{
    lcb_MULTICMD_CTX *mctx = NULL;
    lcb_CMDENDURE dcmd = { 0 };
    lcb_durability_opts_t dopts = { 0 };
    char persist_to = 0, replicate_to = 0;
    lcb_error_t err = LCB_SUCCESS;
    SV *optsv;

    optsv = *av_fetch(resobj, PLCB_RETIDX_OPTIONS, 1);
    if (!SvIOK(optsv)) {
        return 0;
    }

    PLCB_GETDURABILITY(SvUVX(optsv), persist_to, replicate_to);
    if (persist_to == 0 && replicate_to == 0) {
        return 0;
    }
    if (persist_to < 0 || replicate_to < 0) {
        dopts.v.v0.cap_max = 1;
    }

    dopts.v.v0.persist_to = persist_to;
    dopts.v.v0.replicate_to = replicate_to;
    LCB_CMD_SET_KEY(&dcmd, resp->key, resp->nkey);
    dcmd.cas = resp->cas;

    mctx = lcb_endure3_ctxnew(obj->instance, &dopts, &err);
    if (mctx == NULL) {
        plcb_doc_set_err(obj, resobj, err);
        return 0;
    }

    err = mctx->addcmd(mctx, (lcb_CMDBASE *)&dcmd);
    if (err != LCB_SUCCESS) {
        mctx->fail(mctx);
        return 0;
    }

    lcb_sched_enter(obj->instance);
    err = mctx->done(mctx, resp->cookie);
    if (err != LCB_SUCCESS) {
        plcb_doc_set_err(obj, resobj, err);
        return 0;
    }

    lcb_sched_leave(obj->instance);
    return 1;
}

static void
call_helper(AV *resobj, int cbtype, const lcb_RESPBASE *resp)
{
    dSP;
    const char *methname;

    ENTER;
    SAVETMPS;
    PUSHMARK(SP);

    XPUSHs(sv_2mortal(newRV_inc((SV*)resobj)));


    if (cbtype == LCB_CALLBACK_STATS) {
        const lcb_RESPSTATS *sresp = (const void *)resp;

        /** Call as statshelper($doc,$server,$key,$value); */
        XPUSHs(sv_2mortal(newSVpv(sresp->server, 0)));
        XPUSHs(sv_2mortal(newSVpvn(sresp->key, sresp->nkey)));
        if (sresp->value) {
            XPUSHs(sv_2mortal(newSVpvn(sresp->value, sresp->nvalue)));
        }
        methname = PLCB_STATS_PLHELPER;

    } else if (cbtype == LCB_CALLBACK_OBSERVE) {
        const lcb_RESPOBSERVE *oresp = (const void *)resp;

        /** Call as obshelper($doc,$status,$cas,$ismaster) */
        XPUSHs(sv_2mortal(newSVuv(oresp->status)));
        XPUSHs(sv_2mortal(plcb_sv_from_u64_new(&oresp->cas)));
        XPUSHs(oresp->ismaster ? &PL_sv_yes : &PL_sv_no);
        methname = PLCB_OBS_PLHELPER;
    } else {
        return;
    }

    PUTBACK;
    call_pv(methname, G_DISCARD|G_EVAL);
    SPAGAIN;

    if (SvTRUE(ERRSV)) {
        warn("Got error in %s: %s", methname, SvPV_nolen(ERRSV));
    }

    FREETMPS;
    LEAVE;
}

/* This callback is only ever called for single operation, single key results */
static void
callback_common(lcb_t instance, int cbtype, const lcb_RESPBASE *resp)
{
    AV *resobj = (AV *) resp->cookie;
    SV *ctxrv = *av_fetch(resobj, PLCB_RETIDX_PARENT, 0);
    PLCB_t *parent = (PLCB_t *) lcb_get_cookie(instance);
    plcb_OPCTX *ctx = NUM2PTR(plcb_OPCTX*, SvIV(SvRV(ctxrv)));

    plcb_doc_set_err(parent, resobj, resp->rc);

    switch (cbtype) {
    case LCB_CALLBACK_GET: {
        const lcb_RESPGET *gresp = (const lcb_RESPGET *)resp;
        if (resp->rc == LCB_SUCCESS) {
            SV *newval = plcb_convert_retrieval(parent,
                resobj, gresp->value, gresp->nvalue, gresp->itmflags);

            av_store(resobj, PLCB_RETIDX_VALUE, newval);
            plcb_doc_set_cas(parent, resobj, &resp->cas);
        }
        break;
    }

    case LCB_CALLBACK_TOUCH:
    case LCB_CALLBACK_REMOVE:
    case LCB_CALLBACK_UNLOCK:
    case LCB_CALLBACK_STORE:
    case LCB_CALLBACK_ENDURE:
        if (resp->cas) {
            plcb_doc_set_cas(parent, resobj, &resp->cas);
        }

        if (cbtype == LCB_CALLBACK_STORE &&
                chain_endure(parent, resobj, (const lcb_RESPSTORE *)resp)) {
            return; /* Will be handled already */
        }
        plcb_evloop_wait_unref(parent);
        break;

    case LCB_CALLBACK_COUNTER: {
        const lcb_RESPCOUNTER *cresp = (const lcb_RESPCOUNTER*)resp;
        plcb_doc_set_numval(parent, resobj, cresp->value, resp->cas);
        break;
    }

    case LCB_CALLBACK_STATS: {
        const lcb_RESPSTATS *sresp = (const void *)resp;
        if (sresp->server) {
            call_helper(resobj, cbtype, (const lcb_RESPBASE *)sresp);
            return;
        }
        break;
    }
    case LCB_CALLBACK_OBSERVE: {
        const lcb_RESPOBSERVE *oresp = (const lcb_RESPOBSERVE*)resp;
        if (oresp->nkey) {
            call_helper(resobj, cbtype, (const lcb_RESPBASE*)oresp);
            return;
        }
        break;
    }

    default:
        abort();
        break;
    }


    ctx->nremaining--;

    if (ctx->flags & PLCB_OPCTXf_WAITONE) {
        av_push(ctx->ctxqueue, newRV_inc( (SV* )resobj));
        lcb_breakout(instance);
    }

    SvREFCNT_dec(resobj);
}

void
plcb_callbacks_setup(PLCB_t *object)
{
    lcb_t o = object->instance;

    lcb_install_callback3(o, LCB_CALLBACK_GET, callback_common);
    lcb_install_callback3(o, LCB_CALLBACK_GETREPLICA, callback_common);
    lcb_install_callback3(o, LCB_CALLBACK_STORE, callback_common);
    lcb_install_callback3(o, LCB_CALLBACK_TOUCH, callback_common);
    lcb_install_callback3(o, LCB_CALLBACK_REMOVE, callback_common);
    lcb_install_callback3(o, LCB_CALLBACK_COUNTER, callback_common);
    lcb_install_callback3(o, LCB_CALLBACK_UNLOCK, callback_common);
    lcb_install_callback3(o, LCB_CALLBACK_ENDURE, callback_common);
    lcb_install_callback3(o, LCB_CALLBACK_STATS, callback_common);
    lcb_install_callback3(o, LCB_CALLBACK_OBSERVE, callback_common);
}
