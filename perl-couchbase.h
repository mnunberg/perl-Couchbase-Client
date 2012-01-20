#ifndef PERL_COUCHBASE_H_
#define PERL_COUCHBASE_H_

#include <libcouchbase/couchbase.h>
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#define PLCB_RET_CLASSNAME "Couchbase::Client::Return"

#if IVSIZE >= 8
#define PLCB_PERL64
#else
#error "Perl needs 64 bit integer support"
#endif

typedef struct {
	SV *sv; /*pointer to the perl instance*/
	const char *key;
	size_t nkey;
	const char *value;
	size_t nvalue;
	uint64_t cas;
	uint64_t arithmetic;
	libcouchbase_error_t err;
} PLCB_sync_t;

#define plcb_sync_cast(p) (PLCB_sync_t*)(p)
#define plcb_sync_initialize(syncp, self_sv, k, ksz) \
    syncp->sv = self_sv; \
    syncp->key = k; \
    syncp->nkey = ksz; \
    syncp->cas = syncp->nvalue = 0; \
    syncp->value = NULL; \
    syncp->err = 0; \
	syncp->arithmetic = 0;

typedef struct {
    libcouchbase_t instance; /*our library handle*/
    PLCB_sync_t sync; /*object to collect results from callbacks*/
    AV *errors; /*per-operation error stack*/
    HV *ret_stash; /*stash with which we bless our return objects*/
    int flags;
} PLCB_t;

typedef enum {
    PLCB_QUANTITY_SINGLE = 0,
    PLCB_QUANTITY_MULTI  = 1,
} PLCB_quantity_t;

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

void plcb_setup_callbacks(PLCB_t *object);

#endif /* PERL_COUCHBASE_H_ */
