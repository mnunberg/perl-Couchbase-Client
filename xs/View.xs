#include "perl-couchbase.h"

MODULE = Couchbase::View PACKAGE = Couchbase::View PREFIX = PLCBCH_

PROTOTYPES: DISABLE

void
PLCBCH_prepare(PLCB_viewhandle_t *handle, const char* method, \
    PLCB_XS_STRING_NONULL_t path, PLCB_XS_STRING_t body)

    CODE:
    plcb_couch_handle_execute_chunked_init(handle, method,
            path.base, path.len, body.base, body.len);
    av_store(handle->plpriv, PLCB_COUCHIDX_PATH, newSVsv(path.origsv));
    CLEANUP:
    /* Nothing here */

int
PLCBCH__iter_step(PLCB_viewhandle_t *handle)

    CODE:
    RETVAL = plcb_couch_handle_execute_chunked_step(handle);
    OUTPUT: RETVAL


void
PLCBCH_slurp(PLCB_viewhandle_t *handle, const char* method, \
    PLCB_XS_STRING_NONULL_t path, PLCB_XS_STRING_t body)

    CODE:
    av_store(handle->plpriv, PLCB_COUCHIDX_PATH, newSVsv(path.origsv));
    plcb_couch_handle_execute_all(handle, method,
            path.base, path.len, body.base, body.len);

void
PLCBCH_stop(PLCB_viewhandle_t *handle)
    CODE:
    plcb_couch_handle_finish(handle);

SV *
PLCBCH_info(PLCB_viewhandle_t *handle)

    CODE:
    RETVAL = newRV_inc((SV*)handle->plpriv);
    OUTPUT: RETVAL

void
PLCBCH_DESTROY(PLCB_viewhandle_t *handle)

    CODE:
    plcb_couch_handle_free(handle);

SV *
PLCBCH_error(PLCB_viewhandle_t *handle)

    CODE:
    if ( (handle->flags & PLCB_COUCHREQf_ERROR) == 0) {
        RETVAL = &PL_sv_undef;
    } else {
        RETVAL = newRV_inc((SV*)handle->plpriv);
    }

    OUTPUT: RETVAL

void
PLCBCH__iter_pause(PLCB_viewhandle_t *handle)
    CODE:
    /**
     * This sets the flag to stop iterating. This should only
     * be called from within the private handle perl callbacks (hence
     * the leading underscore).
     *
     * Each time the user requests a blocking operation (i.e. _iter_step),
     * The STOPITER* flags are unset.
     *
     * When the C code (i.e. the libcouchbase callback) is done calling
     * the Perl callback, it will check to see if the STOPITER flag is set again,
     * and if it is, it will tell the event loop to stop (or more specifically,
     * decrement the event loop's wait count)
     */
    if ( (handle->flags & PLCB_COUCHREQf_STOPITER_NOOP) == 0) {
        handle->flags |= PLCB_COUCHREQf_STOPITER;
    }
