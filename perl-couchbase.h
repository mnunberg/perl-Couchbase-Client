#ifndef PERL_COUCHBASE_H_
#define PERL_COUCHBASE_H_

#include <libcouchbase/couchbase.h>
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

typedef struct {
	SV *sv; /*pointer to the perl instance*/
	
	const char *key;
	size_t nkey;
	const char *value;
	size_t nvalue;
	uint64_t cas;
	libcouchbase_error_t err;
} PLCB_sync_t;

#define plcb_sync_cast(p) (PLCB_sync_t*)(p)
#define plcb_sync_initialize(syncp, self_sv, k, ksz) \
    syncp->sv = self_sv; \
    syncp->key = k; \
    syncp->nkey = ksz; \
    syncp->cas = syncp->nvalue = 0; \
    syncp->value = NULL; \
    syncp->err = 0;

typedef struct {
    libcouchbase_t instance;
    AV *errors;
    HV *ret_stash;
    int flags;
} PLCB_t;

typedef enum {
    PLCB_CTORIDX_SERVERS,
    PLCB_CTORIDX_USERNAME,
    PLCB_CTORIDX_PASSWORD,
    PLCB_CTORIDX_BUCKET,
    PLCB_CTORIDX_DIE_ON_ERROR
} PLCB_ctor_idx_t;

typedef enum {
    PLCB_RETIDX_VALUE   = 0,
    PLCB_RETIDX_ERRNUM  = 1,
    PLCB_RETIDX_ERRSTR  = 2,
    PLCB_RETIDX_CAS     = 3,
} PLCB_ret_idx_t;

#endif /* PERL_COUCHBASE_H_ */
