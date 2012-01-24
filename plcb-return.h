#ifndef PLCB_RETURN_H_
#define PLCB_RETURN_H_

#include "plcb-util.h"

typedef enum {
    PLCB_RETIDX_VALUE   = 0,
    PLCB_RETIDX_ERRNUM  = 1,
    PLCB_RETIDX_ERRSTR  = 2,
    PLCB_RETIDX_CAS     = 3,
} PLCB_ret_idx_t;

#define plcb_ret_set_cas(obj, ret, cas) \
	av_store(ret, PLCB_RETIDX_CAS, newSVpvn((char*)cas, 8));

#define plcb_ret_set_strval(obj, ret, value, nvalue, flags, cas) \
    av_store(ret, PLCB_RETIDX_VALUE, \
		plcb_convert_retrieval(obj, value, nvalue, flags)); \
	plcb_ret_set_cas(obj, ret, &cas);

static inline void
plcb_ret_set_numval(PLCB_t *obj, AV *ret, uint64_t value, uint64_t cas)
{
    SV *isv = newSV(0);
    plcb_sv_from_u64(isv, value);
    av_store(ret, PLCB_RETIDX_VALUE, isv);
    plcb_ret_set_cas(obj, ret, &cas);
}


#define plcb_ret_set_err(obj, ret, err) \
	av_store(ret, PLCB_RETIDX_ERRNUM, newSViv(err)); \
	if(err != LIBCOUCHBASE_SUCCESS) { \
		av_store(ret, PLCB_RETIDX_ERRSTR, \
		newSVpv(libcouchbase_strerror(obj->instance, err), 0)); \
	}

#endif /*PLCB_RETURN_H_*/