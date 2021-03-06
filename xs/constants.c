#include "perl-couchbase.h"
#include <libcouchbase/vbucket.h>
#include <libcouchbase/views.h>

/* This code will define all the various constants used by the library.
 * We define it here
 */

void
plcb_define_constants(void)
{
    HV *priv_stash = gv_stashpv(PLCB_PRIV_CONSTANTS_PKG, GV_ADD);
    HV *pub_stash = gv_stashpv(PLCB_PUB_CONSTANTS_PKG, GV_ADD);
    AV *our_public = get_av(PLCB_PUB_CONSTANTS_PKG "::EXPORT", GV_ADD);
    AV *our_private = get_av(PLCB_PRIV_CONSTANTS_PKG "::EXPORT", GV_ADD);
    HV *async_stash = gv_stashpv(PLCB_IOPROCS_CONSTANTS_CLASS, GV_ADD);
    AV *our_async = get_av(PLCB_IOPROCS_CONSTANTS_CLASS "::EXPORT", GV_ADD);

    #define ADD_PUBLIC(n, v) \
        newCONSTSUB(pub_stash, n, newSViv(v)); \
        av_push(our_public, newSVpvs(n));

    #define ADD_PRIVATE(n, v) \
        newCONSTSUB(priv_stash, n, newSViv(v)); \
        av_push(our_private, newSVpvs(n));

    #define DEF_ASYNC(n) \
        newCONSTSUB(async_stash, "COUCHBASE_"#n, newSViv(PLCB_##n)); \
        av_push(our_async, newSVpvs("COUCHBASE_"#n));

    #define DEF_PRIV(nbase) ADD_PRIVATE(#nbase, PLCB_##nbase)
    #define ADD_PUB_LCB(n) ADD_PUBLIC("COUCHBASE_" #n, LCB_##n)
    #define ADD_PRIV_LCB(n) ADD_PRIVATE(#n, n)

    DEF_PRIV(RETIDX_VALUE);
    DEF_PRIV(RETIDX_ERRNUM);
    DEF_PRIV(RETIDX_KEY);
    DEF_PRIV(RETIDX_FMTSPEC);
    DEF_PRIV(RETIDX_CAS);
    DEF_PRIV(RETIDX_EXP);

    DEF_PRIV(VHIDX_PATH);
    DEF_PRIV(VHIDX_PARENT);
    DEF_PRIV(VHIDX_PLPRIV);
    DEF_PRIV(VHIDX_ROWBUF);
    DEF_PRIV(VHIDX_PRIVCB);
    DEF_PRIV(VHIDX_META);
    DEF_PRIV(VHIDX_RC);
    DEF_PRIV(VHIDX_HTCODE);
    DEF_PRIV(VHIDX_ISDONE);

    DEF_PRIV(HTIDX_HEADERS);
    DEF_PRIV(HTIDX_STATUS);

    /* View query options */
    ADD_PRIV_LCB(LCB_CMDVIEWQUERY_F_NOROWPARSE);
    ADD_PRIV_LCB(LCB_CMDVIEWQUERY_F_INCLUDE_DOCS);
    ADD_PRIV_LCB(LCB_CMDVIEWQUERY_F_SPATIAL);
    ADD_PRIV_LCB(LCB_N1P_QUERY_STATEMENT);
    ADD_PRIV_LCB(LCB_N1P_QUERY_PREPARED);

    ADD_PRIV_LCB(LCB_HTTP_METHOD_GET);
    ADD_PRIV_LCB(LCB_HTTP_METHOD_POST);
    ADD_PRIV_LCB(LCB_HTTP_METHOD_PUT);
    ADD_PRIV_LCB(LCB_HTTP_METHOD_DELETE);

    ADD_PRIV_LCB(LCB_HTTP_TYPE_VIEW);
    ADD_PRIV_LCB(LCB_HTTP_TYPE_MANAGEMENT);
    ADD_PRIV_LCB(LCB_HTTP_TYPE_RAW);

    DEF_PRIV(CONVERTERS_JSON);
    DEF_PRIV(CONVERTERS_CUSTOM);
    DEF_PRIV(CONVERTERS_STORABLE);

    DEF_PRIV(SETTING_INT);
    DEF_PRIV(SETTING_UINT);
    DEF_PRIV(SETTING_U32);
    DEF_PRIV(SETTING_SIZE);
    DEF_PRIV(SETTING_TIMEOUT);
    DEF_PRIV(SETTING_STRING);

    DEF_PRIV(OPCTXIDX_REMAINING);
    DEF_PRIV(OPCTXIDX_FLAGS);
    DEF_PRIV(OPCTXIDX_QUEUE);
    DEF_PRIV(OPCTXIDX_CBO);

    DEF_PRIV(OPCTXf_IMPLICIT);
    DEF_PRIV(OPCTXf_WAITONE);

    ADD_PRIVATE("SVCTYPE_MGMT", LCBVB_SVCTYPE_MGMT);
    ADD_PRIVATE("SVCTYPE_DATA", LCBVB_SVCTYPE_DATA);
    ADD_PRIVATE("SVCTYPE_VIEWS", LCBVB_SVCTYPE_VIEWS);
    ADD_PRIVATE("SVCMODE_SSL", LCBVB_SVCMODE_SSL);
    ADD_PRIVATE("SVCMODE_PLAIN", LCBVB_SVCMODE_PLAIN);

    /* Public constants */
    ADD_PUBLIC("COUCHBASE_FMT_JSON", PLCB_CF_JSON);
    ADD_PUBLIC("COUCHBASE_FMT_BYTES", PLCB_CF_RAW);
    ADD_PUBLIC("COUCHBASE_FMT_RAW", PLCB_CF_RAW);
    ADD_PUBLIC("COUCHBASE_FMT_UTF8", PLCB_CF_UTF8);
    ADD_PUBLIC("COUCHBASE_FMT_STORABLE", PLCB_CF_STORABLE);

    /* Error Codes */
    ADD_PUB_LCB(SUCCESS);
    ADD_PUB_LCB(AUTH_ERROR);
    ADD_PUB_LCB(DELTA_BADVAL);
    ADD_PUB_LCB(E2BIG);
    ADD_PUB_LCB(EINVAL);
    ADD_PUB_LCB(ENOMEM);
    ADD_PUB_LCB(CLIENT_ENOMEM);
    ADD_PUB_LCB(ETMPFAIL);
    ADD_PUB_LCB(CLIENT_ETMPFAIL);
    ADD_PUB_LCB(KEY_EEXISTS);
    ADD_PUB_LCB(KEY_ENOENT);
    ADD_PUB_LCB(BUCKET_ENOENT);
    ADD_PUB_LCB(NOT_STORED);
    ADD_PUB_LCB(NETWORK_ERROR);
    ADD_PUB_LCB(ETIMEDOUT);
    ADD_PUB_LCB(CONNECT_ERROR);

    DEF_ASYNC(EVIDX_FD);
    DEF_ASYNC(EVIDX_DUPFH);
    DEF_ASYNC(EVIDX_WATCHFLAGS);
    DEF_ASYNC(EVIDX_PLDATA);
    DEF_ASYNC(EVIDX_TYPE);
    DEF_ASYNC(EVIDX_OPAQUE);
    DEF_ASYNC(EVIDX_MAX);

    DEF_ASYNC(EVACTION_WATCH);
    DEF_ASYNC(EVACTION_UNWATCH);
    DEF_ASYNC(EVACTION_INIT);
    DEF_ASYNC(EVACTION_CLEANUP);
    DEF_ASYNC(EVTYPE_IO);
    DEF_ASYNC(EVTYPE_TIMER);
    DEF_ASYNC(READ_EVENT);
    DEF_ASYNC(WRITE_EVENT);
}
