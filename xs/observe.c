#include "perl-couchbase.h"

/**
 * Observe implementation:
 * 
 * Here we will utilize the 'Value' field and convert it into a hash of items
 * indexed by the server; the values will be the key state and the CAS found
 * in each of them. This may be built upon for later analysis by user code.
 */


void plcb_observe_result(PLCB_obs_t *obs, const lcb_observe_resp_t *resp)
{

#define incr_key(k) \
    tmpsv = hv_fetchs(res, k, 1); \
    if (SvTYPE(*tmpsv) == SVt_IV) { \
        SvIVX(*tmpsv)++; \
    } else { \
        sv_setiv(*tmpsv, 1); \
    }

    SV **tmpsv;
    HV *res = (HV*) SvRV(*av_fetch(obs->sync.ret, PLCB_RETIDX_VALUE, 0));

    if (resp->v.v0.from_master &&
            resp->v.v0.cas &&
            obs->orig_cas &&
            obs->orig_cas != resp->v.v0.cas) {
        plcb_ret_set_err(obs->sync.parent, obs->sync.ret, LCB_KEY_EEXISTS);
        return;
    }

    if (resp->v.v0.status & LCB_OBSERVE_PERSISTED) {
        incr_key(PLCB_OBS_NPERSIST);
        if (resp->v.v0.from_master) {
            hv_stores(res, PLCB_OBS_PERSIST_MASTER, &PL_sv_yes);
        } else {
            incr_key(PLCB_OBS_NREPLICATE);
        }
    }

    if (resp->v.v0.status == LCB_OBSERVE_FOUND) {
        if (resp->v.v0.from_master == 0) {
            incr_key(PLCB_OBS_NREPLICATE);
        }
    }
}
