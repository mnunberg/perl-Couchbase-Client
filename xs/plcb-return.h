#ifndef PLCB_RETURN_H_
#define PLCB_RETURN_H_

#include "plcb-util.h"

#define plcb_ret_isa(obj, ret) \
    (sv_isobject(ret) && \
            (SvSTASH(ret) == (obj)->ret_stash || sv_isa(ret, PLCB_RET_CLASSNAME)))

#define plcb_opctx_isa(obj, ret) \
    (sv_isobject(ret) && \
            (SvSTASH(ret) == (obj)->opctx_sync_stash || sv_isa(ret, PLCB_OPCTX_CLASSNAME)))

#define plcb_ret_set_cas(obj, ret, cas) \
    av_store(ret, PLCB_RETIDX_CAS, \
        plcb_sv_from_u64_new(cas) );

static inline void
plcb_ret_set_numval(PLCB_t *obj, AV *ret, uint64_t value, uint64_t cas)
{
    SV *isv = newSV(0);
#ifdef PLCB_PERL64
    sv_setuv(isv, value);
#else
    if (value < UINT32_MAX) {
        sv_setuv(isv, value);
    } else {
        sv_setpvf(isv, "%llu", value);
    }
#endif
    av_store(ret, PLCB_RETIDX_VALUE, isv);
    plcb_ret_set_cas(obj, ret, &cas);
}


#define plcb_ret_set_err(obj, ret, err) sv_setiv(*av_fetch(ret, PLCB_RETIDX_ERRNUM, 1), err)

#define plcb_ret_blessed_rv(obj, ret) \
    sv_bless(newRV_noinc( (SV*)(ret)), (obj)->ret_stash)

#endif /*PLCB_RETURN_H_*/
