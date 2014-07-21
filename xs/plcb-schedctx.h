#ifndef PLCB_ARGLIST_H
#define PLCB_ARGLIST_H
#include "perl-couchbase.h"

typedef struct {
    int cmd;

    union {
        lcb_CMDBASE base;
        lcb_CMDGET get;
        lcb_CMDSTORE store;
        lcb_CMDTOUCH touch;
        lcb_CMDCOUNTER counter;
        lcb_CMDOBSERVE observe;
    } u_template;

    SV *keys;
    HV *cmdopts;
    U32 wantret; /* Value of GIMME_V */
} PLCB_args_t;

/** Populate the argument stack with options */
#define PLCB_ARGS_FROM_STACK(startpos, args, usage) \
if (items > startpos + 1) { die(usage); } \
if (items == startpos+1) { \
    /* Have options */ \
    SV *plcb__tmpsv = ST(startpos); \
    if (!SvROK(plcb__tmpsv)) { \
        die("Options must be a HASH reference"); \
    } \
    plcb__tmpsv = SvRV(plcb__tmpsv); \
    if (SvTYPE(plcb__tmpsv) != SVt_PVHV) { \
        die("Options must be a HASH reference"); \
    } \
    (args)->cmdopts = (HV *)plcb__tmpsv; \
}


/**
 * Structure used for iteration over a list of items. You are responsible
 * for filling in the fields and modifying it during runtime
 */
typedef struct {
    /** Dummy pointer. Use this for whatever you want */
    void *cookie;
    void *priv;

    /** Parent structure */
    PLCB_t *parent;

    /**Set to true by plcb_argiter_start(). Set this to false in the callback
     * to abort iteration. */
    int loop;

    /** Existing flags */
    int flags;

    /** The command used */
    int cmdbase;

    /** Total number of items passed */
    int nreq;

    PLCB_sync_t *sync;
    lcb_error_t err;
    PLCB_args_t *args;
    SV *obj;
    SV *blessed;
} PLCB_schedctx_t;

/** Callback invoked by plcb_argiter_run().
 * @param iter the iterator object
 * @param key The key
 * @param nkey The length of the key
 * @param optsv An SV containing options for the current key. May be NULL.
 */
typedef void (*plcb_iter_cb)(PLCB_schedctx_t *iter,
        const char *key, lcb_SIZE nkey,
        SV *docret, SV *optsv);

/* Ok that keys are 'bare' and that the iterator is an AV, not an HV */
#define PLCB_ARGITERf_RAWKEY_OK 0x01

/* Ok that values are raw SVs and not a reference type */
#define PLCB_ARGITERf_RAWVAL_OK 0x02

/* Ok if the actual SV is a single value */
#define PLCB_ARGITERf_SINGLE_OK 0x04

/* Internal flag set _if_ the SV is actually a single value */
#define PLCB_ARGITERf_SINGLE 0x08

#define PLCB_ARGITERf_DUP_RET 0x10

/**
 * Initalize the iterator for the list of keys. The iterator
 * should have been cleared and its relevant flags and fields set
 */
void
plcb_schedctx_iter_start(PLCB_schedctx_t *ctx);

void
plcb_schedctx_iter_run(PLCB_schedctx_t *iter, plcb_iter_cb callback);

void
plcb_schedctx_iter_bail(PLCB_schedctx_t *ctx, lcb_error_t err);

SV *
plcb_schedctx_return(PLCB_schedctx_t *ctx);
void
plcb_schedctx_init_common(PLCB_t *obj, PLCB_args_t *args,
    PLCB_sync_t *sync, PLCB_schedctx_t *ctx);
#endif
