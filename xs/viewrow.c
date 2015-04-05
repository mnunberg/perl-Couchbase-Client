#include "perl-couchbase.h"
#include <libcouchbase/views.h>
#include <libcouchbase/n1ql.h>

static void
rowreq_init_common(PLCB_t *parent, AV *req)
{
    SV *selfref;

    av_fill(req, PLCB_VHIDX_MAX);
    av_store(req, PLCB_VHIDX_ROWBUF, newRV_noinc((SV *)newAV()));
    av_store(req, PLCB_VHIDX_RAWROWS, newRV_noinc((SV *)newAV()));
    av_store(req, PLCB_VHIDX_PARENT, newRV_inc(parent->selfobj));

    selfref = newRV_inc((SV*)req);
    sv_rvweaken(selfref);
    av_store(req, PLCB_VHIDX_SELFREF, selfref);
}

static PLCB_t *
parent_from_req(AV *req)
{
    SV **pp = av_fetch(req, PLCB_VHIDX_PARENT, 0);
    return NUM2PTR(PLCB_t*,SvUV(SvRV(*pp)));
}

/* Handles the row, adding it into the internal structure */
static void
invoke_row(AV *req, SV *reqrv, SV *rowsrv)
{
    SV *meth;

    dSP;
    ENTER;
    SAVETMPS;
    PUSHMARK(SP);

    /* First arg */
    XPUSHs(reqrv);

    meth = *av_fetch(req, PLCB_VHIDX_PRIVCB, 0);
    if (rowsrv) {
        XPUSHs(rowsrv);
    }

    PUTBACK;
    call_sv(meth, G_DISCARD|G_EVAL);
    SPAGAIN;

    if (SvTRUE(ERRSV)) {
        warn("Got error in %s", SvPV_nolen(ERRSV));
    }

    if (rowsrv) {
        av_clear((AV *)SvRV(rowsrv));
    }

    FREETMPS;
    LEAVE;
}

/* Wraps the buf:length pair as an SV */
static SV *
sv_from_rowdata(const char *s, size_t n)
{
    if (s && n) {
        SV *ret = newSVpvn(s, n);
        SvUTF8_on(ret);
        return ret;
    } else {
        return SvREFCNT_inc(&PL_sv_undef);
    }
}

static void
viewrow_callback(lcb_t obj, int ct, const lcb_RESPVIEWQUERY *resp)
{
    AV *req = resp->cookie;
    SV *req_weakrv = *av_fetch(req, PLCB_VHIDX_SELFREF, 0);
    SV *rawrows_rv = *av_fetch(req, PLCB_VHIDX_RAWROWS, 0);
    AV *rawrows = (AV *)SvRV(rawrows_rv);

    PLCB_t *plobj = parent_from_req(req);

    plcb_views_waitdone(plobj);

    if (resp->rflags & LCB_RESP_F_FINAL) {
        av_store(req, PLCB_VHIDX_VHANDLE, SvREFCNT_inc(&PL_sv_undef));

        /* Flush any remaining rows.. */
        invoke_row(req, req_weakrv, rawrows_rv);

        av_store(req, PLCB_VHIDX_ISDONE, SvREFCNT_inc(&PL_sv_yes));
        av_store(req, PLCB_VHIDX_RC, newSViv(resp->rc));
        av_store(req, PLCB_VHIDX_META, sv_from_rowdata(resp->value, resp->nvalue));

        if (resp->htresp) {
            av_store(req, PLCB_VHIDX_HTCODE, newSViv(resp->htresp->htstatus));
        }
        invoke_row(req, req_weakrv, NULL);
        SvREFCNT_dec(req);
    } else {
        HV *rowdata = newHV();
        /* Key, Value, Doc ID, Geo, Doc */
        hv_stores(rowdata, "key", sv_from_rowdata(resp->key, resp->nkey));
        hv_stores(rowdata, "value", sv_from_rowdata(resp->value, resp->nvalue));
        hv_stores(rowdata, "geometry", sv_from_rowdata(resp->geometry, resp->ngeometry));
        hv_stores(rowdata, "id", sv_from_rowdata(resp->docid, resp->ndocid));

        if (resp->docresp && resp->docresp->rc == LCB_SUCCESS) {
            hv_stores(rowdata, "__doc__",
                newSVpvn(resp->docresp->value, resp->docresp->nvalue));
        }
        av_push(rawrows, newRV_noinc((SV*)rowdata));
        if (av_len(rawrows) >= 1) {
            invoke_row(req, req_weakrv, rawrows_rv);
        }
    }
}

SV *
PLCB__viewhandle_new(PLCB_t *parent,
    const char *ddoc, const char *view, const char *options, int flags)
{
    AV *req = NULL;
    SV *blessed;
    lcb_CMDVIEWQUERY cmd = { 0 };
    lcb_VIEWHANDLE vh = NULL;
    lcb_error_t rc;

    req = newAV();
    rowreq_init_common(parent, req);
    blessed = newRV_noinc((SV*)req);
    sv_bless(blessed, parent->view_stash);

    lcb_view_query_initcmd(&cmd, ddoc, view, options, viewrow_callback);
    cmd.cmdflags = flags; /* Trust lcb on this */
    cmd.handle = &vh;

    rc = lcb_view_query(parent->instance, req, &cmd);

    if (rc != LCB_SUCCESS) {
        SvREFCNT_dec(blessed);
        die("Couldn't issue view query: (0x%x): %s", rc, lcb_strerror(NULL, rc));
    } else {
        SvREFCNT_inc(req); /* For the callback */
        av_store(req, PLCB_VHIDX_VHANDLE, newSVuv(PTR2UV(vh)));
    }
    return blessed;
}

void
PLCB__viewhandle_fetch(SV *pp)
{
    AV *req = (AV *)SvRV(pp);
    PLCB_t *parent = parent_from_req(req);
    plcb_views_wait(parent);
}

void
PLCB__viewhandle_stop(SV *pp)
{
    AV *req = (AV *)SvRV(pp);
    PLCB_t *parent = parent_from_req(req);
    SV *vhsv = *av_fetch(req, PLCB_VHIDX_VHANDLE, 0);

    if (SvIOK(vhsv)) {
        lcb_VIEWHANDLE vh = NUM2PTR(lcb_VIEWHANDLE, SvUV(vhsv));
        lcb_view_cancel(parent->instance, vh);
        av_store(req, PLCB_VHIDX_VHANDLE, SvREFCNT_inc(&PL_sv_undef));
        av_store(req, PLCB_VHIDX_ISDONE, SvREFCNT_inc(&PL_sv_yes));
        SvREFCNT_dec((SV *)req);
    }
}
