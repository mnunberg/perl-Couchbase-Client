#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "perl-couchbase.h"

void
plcb_evloop_wait_unref(PLCB_t *object)
{
}

/* This callback is only ever called for single operation, single key results */
static void
callback_common(lcb_t instance, int cbtype, const lcb_RESPBASE *resp)
{
    AV *resobj = (AV *) resp->cookie;
    AV *ctx = (AV *)SvRV(*av_fetch(resobj, PLCB_RETIDX_PARENT, 0));

    PLCB_t *parent = (PLCB_t *) lcb_get_cookie(instance);

    plcb_ret_set_err(parent, resobj, resp->rc);

    switch (cbtype) {
    case LCB_CALLBACK_GET: {
        const lcb_RESPGET *gresp = (const lcb_RESPGET *)resp;
        if (resp->rc == LCB_SUCCESS) {
            SV *newval = plcb_convert_retrieval(parent,
                resobj, gresp->value, gresp->nvalue, gresp->itmflags);

            av_store(resobj, PLCB_RETIDX_VALUE, newval);
        }
        plcb_evloop_wait_unref(parent);
        break;
    }

    case LCB_CALLBACK_TOUCH:
    case LCB_CALLBACK_REMOVE:
    case LCB_CALLBACK_UNLOCK:
    case LCB_CALLBACK_STORE:
        plcb_ret_set_cas(parent, resobj, &resp->cas);
        plcb_evloop_wait_unref(parent);
        break;

    case LCB_CALLBACK_COUNTER: {
        const lcb_RESPCOUNTER *cresp = (const lcb_RESPCOUNTER*)resp;
        plcb_ret_set_numval(parent, resobj, cresp->value, resp->cas);
        plcb_evloop_wait_unref(parent);
        break;
    }

    default:
        abort();
        break;
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
}
