#ifndef PERL_COUCHBASE_H_
#define PERL_COUCHBASE_H_

#include <sys/types.h> /*for size_t*/
#include <libcouchbase/couchbase.h>
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

#define PLCB_RET_CLASSNAME "Couchbase::Document"
#define PLCB_ITER_CLASSNAME "Couchbase::DocIterator"

#if IVSIZE >= 8
#define PLCB_PERL64
#endif
#include "plcb-util.h"

typedef struct PLCB_st PLCB_t;

typedef enum {
    PLCB_SYNCTYPE_SINGLE = 0,
    PLCB_SYNCTYPE_MULTI,
    PLCB_SYNCTYPE_ITER
} plcb_synctype_t;

#define PLCB_SYNCf_SINGLERET 0x01
#define PLCB_SYNCf_MULTIRET 0x02
#define PLCB_SYNCf_STOREDUR 0x03

#define PLCB_SYNC_BASE \
    PLCB_t *parent; /**< Parent object */ \
    unsigned type : 2; /**< Type of context */ \
    unsigned flags : 6; /**< Flags for context */ \
    unsigned remaining; /**< How many operations remain for this context */ \
    SV *errsv; /**< SV containing an error to be thrown, if any */ \
    union { \
        AV *ret; /**< For single operation sync objects */ \
        HV *multiret; /**< For multi operation sync objects */ \
    } u

typedef struct {
    PLCB_SYNC_BASE;
} PLCB_sync_t;


#define PLCB_ITER_ERROR -2

typedef struct {
    PLCB_SYNC_BASE;
    /* Because callbacks can be invoked more than once per iteration,
     * the output needs to be buffered. Array of (key, retav (RV)) pairs.
     */
    AV *buffer_av;

    /*
     * In the case of an error in creating the iterator, the error
     * will be placed here
     */
    AV *error_av;

    /* We hold a reference to our parent */
    SV *parent_rv;

    /* If the remaining count is 0 and pl_destroyed is true, then the
     * callback should Safefree() this object without any questions.
     */
    int pl_destroyed;
} PLCB_iter_t;

#define plcb_sync_cast(p) (PLCB_sync_t*)(p)

typedef enum {
    PLCBf_DIE_ON_ERROR          = 0x1,
    /*conversion flags*/
    PLCBf_USE_COMPAT_FLAGS      = 0x2,
    PLCBf_USE_COMPRESSION       = 0x4,
    PLCBf_USE_STORABLE          = 0x8,
    PLCBf_USE_CONVERT_UTF8      = 0x10,
    PLCBf_NO_CONNECT            = 0x20,
    PLCBf_DECONVERT             = 0x40,
    
    /*pseudo-flags*/
    PLCBf_COMPRESS_THRESHOLD    = 0x80,
    PLCBf_RET_EXTENDED_FIELDS   = 0x100,
    
    /* Whether to treat references to string scalars
      as strings */
    PLCBf_DEREF_RVPV            = 0x200,
    
    /* Whether to verify all input for couch* related
      storage operations for valid JSON content */
    PLCBf_JSON_VERIFY           = 0x400,
} PLCB_flags_t;

#define PLCBf_DO_CONVERSION \
    (PLCBf_USE_COMPRESSION|PLCBf_USE_STORABLE|PLCBf_USE_CONVERT_UTF8)

struct PLCB_st {
    lcb_t instance; /*our library handle*/
    PLCB_sync_t sync; /*object to collect results from callbacks*/
    HV *ret_stash; /*stash with which we bless our return objects*/
    HV *iter_stash; /* Stash with which we bless our iterator objects */

    PLCB_flags_t my_flags;

    int connected;
    
    SV *cv_serialize;
    SV *cv_deserialize;
    SV *cv_compress;
    SV *cv_decompress;
    STRLEN compress_threshold;
    
    /*how many operations are pending on this object*/
    int npending;
    
    /* Structure containing specific data for Couch */
    struct {
        /* This will encode references into JSON */
        SV *cv_json_encode;
        /* This will verify that a stored string is indeed JSON, optional */
        SV *cv_json_verify;

        HV *view_stash;
        HV *design_stash;
        HV *handle_av_stash;
    } couch;
};

/*need to include this after defining PLCB_t*/
#include "plcb-return.h"
#include "perl-couchbase-couch.h"
#include "plcb-convert.h"
#include "plcb-schedctx.h"
#include "plcb-args.h"
#include "plcb-commands.h"


/*Change this #define to the last index used by the 'default' constructor*/
#define PLCB_CTOR_STDIDX_MAX 10

typedef enum {
    PLCB_CTORIDX_CONNSTR,
    PLCB_CTORIDX_PASSWORD,
    PLCB_CTORIDX_MYFLAGS,
    PLCB_CTORIDX_STOREFLAGS,
    
    PLCB_CTORIDX_COMP_THRESHOLD,
    PLCB_CTORIDX_COMP_METHODS,
    PLCB_CTORIDX_SERIALIZE_METHODS,
    
    PLCB_CTORIDX_NO_CONNECT,
    PLCB_CTORIDX_JSON_ENCODE_METHOD,
    PLCB_CTORIDX_JSON_VERIFY_METHOD,
    
    PLCB_CTORIDX_STDIDX_MAX = PLCB_CTORIDX_JSON_VERIFY_METHOD
    
} PLCB_ctor_idx_t;

typedef enum {
    PLCB_CONVERT_SPEC_NONE = 0,
    PLCB_CONVERT_SPEC_JSON
} plcb_conversion_spec_t;

typedef time_t PLCB_exp_t;

void plcb_callbacks_setup(PLCB_t *object);

/*options for common constructor settings*/
void plcb_ctor_cbc_opts(AV *options, struct lcb_create_st *cropts);
void plcb_ctor_conversion_opts(PLCB_t *object, AV *options);
void plcb_ctor_init_common(PLCB_t *object, lcb_t instance, AV *options);

/*cleanup functions*/
void plcb_cleanup(PLCB_t *object);

/*conversion functions*/
void
plcb_convert_storage(PLCB_t* object, SV **input_sv, STRLEN *data_len,
    uint32_t *flags, plcb_conversion_spec_t spec);

void plcb_convert_storage_free(PLCB_t *object, SV *output_sv, uint32_t flags);
SV*
plcb_convert_retrieval(PLCB_t *object, const char *data, size_t data_len,
    uint32_t flags);

int plcb_convert_settings(PLCB_t *object, int flag, int new_value);


/**
 * This function decrements the wait count by one, and possibly calls stop_event_loop
 * if the reference count has hit 0.
 */
void plcb_evloop_wait_unref(PLCB_t *obj);

/** Operation functions */
SV *PLCB_op_get(SV*,PLCB_args_t*);
SV *PLCB_op_set(SV*,PLCB_args_t*);
SV *PLCB_op_remove(SV*,PLCB_args_t*);


/**
 * XS prototypes.
 */
XS(boot_Couchbase__Client_couch);
XS(boot_Couchbase__Client_iterator);

#endif /* PERL_COUCHBASE_H_ */
