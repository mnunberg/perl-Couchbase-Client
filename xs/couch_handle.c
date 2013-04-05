#include "perl-couchbase.h"
#include <assert.h>

/** Complete callback checks for data and populates it,
 * data callback will invoke a callback.
 *
 * The actual callbacks are usually private callbacks, which live in
 * Couchbase::Couch::Handle and its subclasses
 */

static void call_to_perl(PLCB_couch_handle_t *handle, int cbidx, SV *datasv, AV *statusav)
{
    SV **tmpsv;
    
    dSP;
    
    tmpsv = av_fetch(statusav, cbidx, 0);
    if (!tmpsv) {
        die("Couldn't invoke callback (none installed)");
    }
    
    ENTER;
    SAVETMPS;
    
    /**
     * callback($handle, $status, $data);
     */

    PUSHMARK(SP);
    XPUSHs(sv_2mortal(newRV_inc(SvRV(handle->self_rv))));
    XPUSHs(sv_2mortal(newRV_inc((SV*)statusav)));
    XPUSHs(sv_2mortal(datasv));
    PUTBACK;
    
    call_sv(*tmpsv, G_DISCARD);
    
    FREETMPS;
    LEAVE;
}

static
void data_callback(lcb_http_request_t couchreq,
                   lcb_t instance,
                   const void *cookie,
                   lcb_error_t error,
                   const lcb_http_resp_t *resp)
{
    PLCB_couch_handle_t *handle = (PLCB_couch_handle_t*)cookie;
    SV **tmpsv;
    SV *datasv;

    if ((handle->flags & PLCB_COUCHREQf_INITIALIZED) == 0) {
        handle->flags |= PLCB_COUCHREQf_INITIALIZED;
        tmpsv = av_fetch(handle->plpriv, PLCB_COUCHIDX_HTTP, 1);
        sv_setiv(*tmpsv, resp->v.v0.status);
    }
    
    if (resp->v.v0.nbytes) {
        datasv = newSVpv((const char*)resp->v.v0.bytes,
                         resp->v.v0.nbytes);
    } else {
        datasv = &PL_sv_undef;
    }


    if (error != LIBCOUCHBASE_SUCCESS) {
        plcb_ret_set_err(handle->parent, handle->plpriv, error);
        lcb_cancel_http_request(handle->parent->instance,
                                couchreq);
        handle->lcb_request = NULL;
        handle->flags |=
                (PLCB_COUCHREQf_TERMINATED |
                PLCB_COUCHREQf_ERROR |
                PLCB_COUCHREQf_STOPITER);
        plcb_evloop_wait_unref(handle->parent);
        call_to_perl(handle, PLCB_COUCHIDX_CALLBACK_COMPLETE, datasv, handle->plpriv);
    } else {
        call_to_perl(handle, PLCB_COUCHIDX_CALLBACK_DATA, datasv, handle->plpriv);

        /* The callback might have requested we stop the event loop. Check this
         * by looking at the STOPITER flag
         */

        if ( (handle->flags & PLCB_COUCHREQf_STOPITER)
                && (handle->flags & PLCB_COUCHREQf_STOPITER_NOOP) == 0) {

            handle->flags &= ~(PLCB_COUCHREQf_STOPITER);
            handle->flags |= PLCB_COUCHREQf_STOPITER_NOOP;

            plcb_evloop_wait_unref(handle->parent);
        }
    }
}

/**
 * This is called when the HTTP response is complete. We only call out to
 * Perl if the request is chunked. Otherwise we reduce the overhead by
 * simply appending data.
 */
static void complete_callback(lcb_http_request_t couchreq,
                              lcb_t instance,
                              const void *cookie,
                              lcb_error_t error,
                              const lcb_http_resp_t *resp)
{
    PLCB_couch_handle_t *handle = (PLCB_couch_handle_t*)cookie;
    lcb_http_status_t status = resp->v.v0.status;

    handle->flags |= PLCB_COUCHREQf_TERMINATED;
    handle->lcb_request = NULL;

    if (error != LIBCOUCHBASE_SUCCESS || (status < 200 && status > 299)) {
        handle->flags |= PLCB_COUCHREQf_ERROR;
    }
    plcb_ret_set_err(handle->parent, handle->plpriv, error);

    if ( (handle->flags & PLCB_COUCHREQf_CHUNKED) == 0) {
        sv_setiv(*( av_fetch(handle->plpriv, PLCB_COUCHIDX_HTTP, 1) ), status);

        if (resp->v.v0.nbytes) {
            SV *datasv;
            datasv = *(av_fetch(handle->plpriv, PLCB_RETIDX_VALUE, 1));
            sv_setpvn(datasv, (const char*)resp->v.v0.bytes,
                      resp->v.v0.nbytes);
        }
        /* Not chunked, decrement reference count */
        plcb_evloop_wait_unref(handle->parent);
    } else {
        /* chunked */

        /* If the chunked mode has errored prematurely, this is where we get the
         * information from..
         */
        sv_setiv(*( av_fetch(handle->plpriv, PLCB_COUCHIDX_HTTP, 1)), status);

        call_to_perl(handle, PLCB_COUCHIDX_CALLBACK_COMPLETE,
                     &PL_sv_undef, handle->plpriv);

        /**
         * Because we might receive this callback in succession to a data
         * callback within the same event loop context, we risk decrementing
         * our wait count by two, which is something we don't want.
         *
         * How to overcome this? Check the STOPITER_NOOP flag. It will
         * be set if the data callback had called iter_pause
         * (see xs/Couch_request_handle.xs)
         */
        if ((handle->flags & PLCB_COUCHREQf_STOPITER_NOOP) == 0) {
            plcb_evloop_wait_unref(handle->parent);
        }
    }
}

SV* plcb_couch_handle_new(HV *stash, SV *cbo_sv, PLCB_t *cbo)
{
    SV *my_iv;
    SV *blessed_rv;
    SV *av_rv;
    AV *retav;
    PLCB_couch_handle_t *newhandle;
    
    assert(stash);
    Newxz(newhandle, 1, PLCB_couch_handle_t);
    
    my_iv = newSViv(PTR2IV(newhandle));
    blessed_rv = newRV_noinc(my_iv);
    sv_bless(blessed_rv, stash);
    SvREFCNT_inc(stash);
    newhandle->self_rv = newRV_inc(my_iv);
    sv_rvweaken(newhandle->self_rv);
    
    retav = newAV();
    av_store(retav, PLCB_COUCHIDX_CBO, newRV_inc(SvRV(cbo_sv)));
    av_store(retav, PLCB_COUCHIDX_HTTP, newSViv(-1));

    newhandle->parent = cbo;
    newhandle->plpriv = retav;
    av_rv = newRV_inc((SV*)retav);
    sv_bless(av_rv, cbo->couch.handle_av_stash);
    return blessed_rv;
}

void plcb_couch_handle_free(PLCB_couch_handle_t *handle)
{
    if (handle->lcb_request) {
        lcb_cancel_http_request(handle->parent->instance,
                                handle->lcb_request);
        handle->lcb_request = NULL;
    }

    if (handle->plpriv) {
        SvREFCNT_dec(handle->plpriv);
        handle->plpriv = NULL;
    }
    if (handle->self_rv) {
        SvREFCNT_dec(handle->self_rv);
        handle->self_rv = NULL;
    }
    Safefree(handle);
}

void plcb_couch_handle_finish(PLCB_couch_handle_t *handle)
{
    if (handle->flags & PLCB_COUCHREQf_TERMINATED) {
        /* already stopped */
        return;
    }

    if ( (handle->flags & PLCB_COUCHREQf_ACTIVE) == 0) {
        return;
    }
    if (handle->lcb_request) {
        lcb_cancel_http_request(handle->parent->instance,
                                handle->lcb_request);
    }
    handle->flags |= PLCB_COUCHREQf_TERMINATED;
}


static void make_http_cmd(lcb_http_method_t method,
                          const char *path, size_t npath,
                          const char *body, size_t nbody,
                          int chunked,
                          lcb_http_cmd_t *cmd)
{
    cmd->v.v0.body = body;
    cmd->v.v0.nbody = nbody;
    cmd->v.v0.path = path;
    cmd->v.v0.npath = npath;
    cmd->v.v0.chunked = chunked;
    cmd->v.v0.method = method;
    cmd->v.v0.content_type = "application/json";
}

/**
 * This invokes a non-chunked request, and waits until all data has
 * arrived. This is less complex and more performant than the incremental
 * variant
 */

void plcb_couch_handle_execute_all(PLCB_couch_handle_t *handle,
                                   lcb_http_method_t method,
                                   const char *path, size_t npath,
                                   const char *body, size_t nbody)
{
    lcb_error_t err;
    lcb_http_cmd_t htcmd = { 0 };
    make_http_cmd(method, path, npath, body, nbody, 0, &htcmd);

    err = lcb_make_http_request(handle->parent->instance,
                                handle,
                                LCB_HTTP_TYPE_VIEW, &htcmd,
                                &handle->lcb_request);

    handle->flags = 0;
    if (err != LIBCOUCHBASE_SUCCESS) {
        warn("Got error!!!");
        plcb_ret_set_err(handle->parent, handle->plpriv, err);
        handle->flags |= (PLCB_COUCHREQf_TERMINATED|PLCB_COUCHREQf_ERROR);
        return;
    }
    
    handle->flags |= PLCB_COUCHREQf_ACTIVE;
    handle->parent->npending++;
    plcb_evloop_start(handle->parent);
}

/**
 * Initializes a handle for chunked/iterative invocation
 */

void plcb_couch_handle_execute_chunked_init(PLCB_couch_handle_t *handle,
                                            lcb_http_method_t method,
                                            const char *path, size_t npath,
                                            const char *body, size_t nbody)
{
    lcb_error_t err;
    handle->flags = PLCB_COUCHREQf_CHUNKED;
    lcb_http_cmd_t htcmd = { 0 };
    make_http_cmd(method, path, npath, body, nbody, 1, &htcmd);
    
    err = lcb_make_http_request(handle->parent->instance, handle,
                                  LCB_HTTP_TYPE_VIEW, &htcmd,
                                  &handle->lcb_request);

    if (err != LIBCOUCHBASE_SUCCESS) {
        /* Pretend we're done, and call the data callback */
        plcb_ret_set_err(handle->parent, handle->plpriv, err);
        call_to_perl(handle, PLCB_COUCHIDX_CALLBACK_COMPLETE,
                     &PL_sv_undef, handle->plpriv);
    }
    
    handle->flags |= PLCB_COUCHREQf_ACTIVE;
}

/**
 * Loops until a callback terminates the current step.
 * This also does some sanity checking and will not invoke the event loop.
 *
 * Returns true if we did something, or 0 if we couldn't
 */

int plcb_couch_handle_execute_chunked_step(PLCB_couch_handle_t *handle)
{
    if (handle->flags & PLCB_COUCHREQf_TERMINATED) {
        return 0;
    }

    handle->parent->npending++;
    handle->flags &= ~(PLCB_COUCHREQf_STOPITER|PLCB_COUCHREQf_STOPITER_NOOP);
    plcb_evloop_start(handle->parent);
    /* Returned? */
    return ((handle->flags & PLCB_COUCHREQf_TERMINATED) == 0);
}

void plcb_couch_callbacks_setup(PLCB_t *object)
{
    lcb_set_http_data_callback(object->instance, data_callback);
    lcb_set_http_complete_callback(object->instance, complete_callback);
}
