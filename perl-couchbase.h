#ifndef PERL_COUCHBASE_H_
#define PERL_COUCHBASE_H_

#include <sys/types.h> /*for size_t*/
#include <libcouchbase/couchbase.h>
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"


#define PLCB_RET_CLASSNAME "Couchbase::Client::Return"
#define PLCB_STATS_SUBNAME "Couchbase::Client::_stats_helper"

#if IVSIZE >= 8
#define PLCB_PERL64
#else
#error "Perl needs 64 bit integer support"
#endif

#include "plcb-util.h"

typedef struct PLCB_st PLCB_t;

typedef struct {
    PLCB_t *parent;
    const char *key;
    size_t nkey;
    const char *value;
    size_t nvalue;
    uint64_t cas;
    uint64_t arithmetic;
    libcouchbase_error_t err;
    uint32_t store_flags;
} PLCB_sync_t;

#define plcb_sync_cast(p) (PLCB_sync_t*)(p)
#define plcb_sync_initialize(syncp, object, k, ksz) \
    syncp->parent = object; \
    syncp->key = k; \
    syncp->nkey = ksz; \
    syncp->cas = syncp->nvalue = 0; \
    syncp->value = NULL; \
    syncp->err = 0; \
    syncp->arithmetic = 0; \
    syncp->store_flags = 0; \

typedef enum {
    PLCBf_DIE_ON_ERROR          = 0x1,
    /*conversion flags*/
    PLCBf_USE_COMPAT_FLAGS      = 0x2,
    PLCBf_USE_COMPRESSION       = 0x4,
    PLCBf_USE_STORABLE          = 0x8,
    PLCBf_USE_CONVERT_UTF8      = 0x10,
    
    PLCBf_NO_CONNECT            = 0x20,
} PLCB_flags_t;

#define PLCBf_DO_CONVERSION \
    (PLCBf_USE_COMPRESSION|PLCBf_USE_STORABLE|PLCBf_USE_CONVERT_UTF8)

struct PLCB_st {
    libcouchbase_t instance; /*our library handle*/
    PLCB_sync_t sync; /*object to collect results from callbacks*/
    HV *stats_hv; /*object to collect statistics from*/
    AV *errors; /*per-operation error stack*/
    HV *ret_stash; /*stash with which we bless our return objects*/
    uint32_t store_flags; /*flags to use when storing values*/
    PLCB_flags_t my_flags;
    
    SV *cv_serialize;
    SV *cv_deserialize;
    SV *cv_compress;
    SV *cv_decompress;
    STRLEN compress_threshold;
    
    /*io operations, needed for starting/stopping the event loop*/
    struct libcouchbase_io_opt_st *io_ops;
    
    /*how many operations are pending on this object*/
    int npending;
};

/*need to include this after defining PLCB_t*/
#include "plcb-return.h"


typedef enum {
    PLCB_QUANTITY_SINGLE = 0,
    PLCB_QUANTITY_MULTI  = 1,
} PLCB_quantity_t;

#define PLCB_STOREf_COMPAT_STORABLE 0x01LU
#define PLCB_STOREf_COMPAT_COMPRESS 0x02LU
#define PLCB_STOREf_COMPAT_UTF8     0x04LU

#define plcb_storeflags_has_compression(obj, flags) \
    (flags & PLCB_STOREf_COMPAT_COMPRESS)
#define plcb_storeflags_has_serialization(obj, flags) \
    (flags & PLCB_STOREf_COMPAT_STORABLE)
#define plcb_storeflags_has_utf8(obj, flags) \
    (flags & PLCB_STOREf_COMPAT_UTF8)

#define plcb_storeflags_has_conversion(obj, flags) \
    (plcb_storeflags_has_serialization(obj,flags) || \
     plcb_storeflags_has_compression(obj,flags)) \
     

#define plcb_should_do_compression(obj, flags) \
    ((obj->my_flags & PLCBf_USE_COMPRESSION) \
    && plcb_storeflags_has_compression(obj, flags))

#define plcb_should_do_serialization(obj, flags) \
    ((obj->my_flags & PLCBf_USE_STORABLE) \
    && plcb_storeflags_has_serialization(obj, flags))

#define plcb_should_do_utf8(obj, flags) \
    ((obj->my_flags & PLCBf_USE_CONVERT_UTF8) \
    && plcb_storeflags_has_utf8(obj, flags))

#define plcb_should_do_conversion(obj, flags) \
    (plcb_should_do_compression(obj,flags) \
    || plcb_should_do_serialization(obj, flags) \
    || plcb_should_do_utf8(obj, flags))

#define plcb_storeflags_apply_compression(obj, flags) \
    flags |= PLCB_STOREf_COMPAT_COMPRESS
#define plcb_storeflags_apply_serialization(obj, flags) \
    flags |= PLCB_STOREf_COMPAT_STORABLE
#define plcb_storeflags_apply_utf8(obj, flags) \
    flags |= PLCB_STOREf_COMPAT_UTF8


/*Change this #define to the last index used by the 'default' constructor*/
#define PLCB_CTOR_STDIDX_MAX 10

typedef enum {
    PLCB_CTORIDX_SERVERS,
    PLCB_CTORIDX_USERNAME,
    PLCB_CTORIDX_PASSWORD,
    PLCB_CTORIDX_BUCKET,
    PLCB_CTORIDX_MYFLAGS,
    PLCB_CTORIDX_STOREFLAGS,
    
    PLCB_CTORIDX_COMP_THRESHOLD,
    PLCB_CTORIDX_COMP_METHODS,
    PLCB_CTORIDX_SERIALIZE_METHODS,
    
    /*provided object for event loop handling*/
    PLCB_CTORIDX_EVLOOP_OBJ,
    
} PLCB_ctor_idx_t;


void plcb_setup_callbacks(PLCB_t *object);

/*options for common constructor settings*/
void plcb_ctor_cbc_opts(AV *options,
    char **hostp, char **userp, char **passp, char **bucketp);
void plcb_ctor_conversion_opts(PLCB_t *object, AV *options);
void plcb_ctor_init_common(PLCB_t *object, libcouchbase_t instance);

/*conversion functions*/
void plcb_convert_storage(
    PLCB_t* object, SV **input_sv, STRLEN *data_len, uint32_t *flags);
void plcb_convert_storage_free(
    PLCB_t *object, SV *output_sv, uint32_t flags);
SV* plcb_convert_retrieval(
    PLCB_t *object, const char *data, size_t data_len, uint32_t flags);



#endif /* PERL_COUCHBASE_H_ */
