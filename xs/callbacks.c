#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "perl-couchbase.h"

void
plcb_evloop_wait_unref(PLCB_t *object)
{
    assert(object->npending);
    object->npending--;
    if (!object->npending) {
        lcb_breakout(object->instance);
    }
}

static void
get_resobj(const lcb_RESPBASE *resp, PLCB_sync_t **sync_p, AV **resobj_p)
{
    PLCB_sync_t *sync;
    AV *resobj;

    sync = resp->cookie;

    if (sync->flags & PLCB_SYNCf_SINGLERET) {
        resobj = sync->u.ret;
    } else {
        SV **ent = hv_fetch(sync->u.multiret, resp->key, resp->nkey, 0);
        if (!ent) {
            die("Missing entry!");
        }
        resobj = (AV*)SvRV((*ent));
    }

    plcb_ret_set_err(sync->parent, resobj, resp->rc);
    *sync_p = sync;
    *resobj_p = resobj;

}

/* This callback is only ever called for single operation, single key results */
static void
callback_common(lcb_t instance, int cbtype, const lcb_RESPBASE *resp)
{
    AV *resobj; /* Result object */
    PLCB_sync_t *sync;

    get_resobj(resp, &sync, &resobj);

    switch (cbtype) {
    case LCB_CALLBACK_GET: {
        const lcb_RESPGET *gresp = (const lcb_RESPGET *)resp;
        if (resp->rc == LCB_SUCCESS) {
            plcb_ret_set_strval(sync->parent,
                resobj, gresp->value, gresp->nvalue, gresp->itmflags, gresp->cas);
        }
        plcb_evloop_wait_unref(sync->parent);
        break;
    }
    case LCB_CALLBACK_TOUCH:
    case LCB_CALLBACK_REMOVE:
    case LCB_CALLBACK_UNLOCK:
    case LCB_CALLBACK_STORE:
        plcb_ret_set_cas(sync->parent, resobj, &resp->cas);
        plcb_evloop_wait_unref(sync->parent);
        break;

    case LCB_CALLBACK_COUNTER: {
        const lcb_RESPCOUNTER *cresp = (const lcb_RESPCOUNTER*)resp;
        plcb_ret_set_numval(sync->parent, resobj, cresp->value, resp->cas);
        plcb_evloop_wait_unref(sync->parent);
        break;
    }
    default:
        abort();
        break;
    }
}

static void
observe_callback(lcb_t instance, int cbtype, const lcb_RESPOBSERVE *resp)
{
    PLCB_sync_t *sync;
    AV *resobj;
    AV *curval;
    SV *currv;
    SV *tmp;
    HV *obsinfo;

    get_resobj((const lcb_RESPBASE*)resp, &sync, &resobj);
    if (resp->rflags & LCB_RESP_F_FINAL) {
        plcb_evloop_wait_unref(sync->parent);
        return;
    }

    if (resp->rc != LCB_SUCCESS) {
        return;
    }

    currv = *av_fetch(resobj, PLCB_RETIDX_VALUE, 1);
    if (!SvOK(currv)) {
        SV *tmprv;
        curval = newAV();
        tmprv = newRV_noinc((SV*)curval);

        SvSetSV(currv, tmprv);
        SvREFCNT_dec(tmprv);
    } else {
        curval = (AV*)SvRV(currv);
    }

    /* Create the HV */
    obsinfo = newHV();
    av_push(curval, newRV_noinc((SV*)obsinfo));
    hv_stores(obsinfo, "CAS", plcb_sv_from_u64_new(&resp->cas));
    hv_stores(obsinfo, "Status", newSVuv(resp->status));

    tmp = resp->ismaster ? &PL_sv_yes : &PL_sv_no;
    SvREFCNT_inc(tmp);
    hv_stores(obsinfo, "Master", tmp);
}

static void
stats_callback(lcb_t instance, int cbtype, const lcb_RESPSTATS *resp)
{
    PLCB_sync_t *sync;
    AV *resobj;
    SV *cur;
    HV *keys;
    HV *srvhash;

    get_resobj((const lcb_RESPBASE*)resp, &sync, &resobj);
    cur = *av_fetch(resobj, PLCB_RETIDX_VALUE, 1);
    if (!SvOK(cur)) {
        SV *tmprv = newRV_noinc((SV*)newHV());
        SvSetSV(cur, tmprv);
        SvREFCNT_dec(tmprv);
    }

    keys = (HV*)SvRV(cur);
    /* Find the current stat key */
    cur = *hv_fetch(keys, resp->key, resp->nkey, 1);
    if (!SvOK(cur)) {
        SV *tmprv = newRV_noinc((SV*)newHV());
        SvSetSV(cur, tmprv);
        SvREFCNT_dec(tmprv);
    }
    srvhash = (HV *)SvRV(cur);
    /* Find the server */
    cur = *hv_fetch(srvhash, resp->server, strlen(resp->server), 1);
    sv_setpvn(cur, resp->value, resp->nvalue);
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

    /* Special */
    lcb_install_callback3(o, LCB_CALLBACK_OBSERVE, (lcb_RESPCALLBACK)observe_callback);
    lcb_install_callback3(o, LCB_CALLBACK_STATS, (lcb_RESPCALLBACK)stats_callback);
}
