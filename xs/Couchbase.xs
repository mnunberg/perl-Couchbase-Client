#include "perl-couchbase.h"
#include "plcb-util.h"

static int PLCB_connect(PLCB_t* self);

void plcb_cleanup(PLCB_t *object)
{
    if (object->instance) {
        lcb_destroy(object->instance);
        object->instance = NULL;
    }

    #define _free_cv(fld) if (object->fld) { SvREFCNT_dec(object->fld); object->fld = NULL; }
    _free_cv(cv_serialize); _free_cv(cv_deserialize);
    _free_cv(cv_jsonenc); _free_cv(cv_jsondec);
    _free_cv(cv_customenc); _free_cv(cv_customdec);
    #undef _free_cv
}

static SV *
new_opctx(PLCB_t *parent, int flags)
{
    plcb_OPCTX *ctx;
    Newxz(ctx, 1, plcb_OPCTX);

    SV *blessed = newSV(0);
    sv_setiv(blessed, PTR2IV(ctx));
    blessed = newRV_noinc(blessed);
    sv_bless(blessed, parent->opctx_sync_stash);

    ctx->flags = flags;
    ctx->parent = newRV_inc(parent->selfobj);
    sv_rvweaken(ctx->parent);

    return blessed;
}

static void
clear_opctx(PLCB_t *parent)
{
    if (!parent->curctx) {
        return;
    }
    SvREFCNT_dec(parent->curctx);
    parent->curctx = NULL;

}

/*Construct a new libcouchbase object*/
static SV *
PLCB_construct(const char *pkg, HV *hvopts)
{
    lcb_t instance;
    lcb_error_t err;
    struct lcb_create_st cr_opts = { 0 };
    SV *blessed_obj;
    PLCB_t *object;
    plcb_argval_t options[] = {
        PLCB_KWARG("connstr", CSTRING, &cr_opts.v.v3.connstr),
        PLCB_KWARG("password", CSTRING, &cr_opts.v.v3.passwd),
        { NULL }
    };

    cr_opts.version = 3;
    plcb_extract_args((SV*)hvopts, options);
    err = lcb_create(&instance, &cr_opts);

    if (!instance) {
        die("Failed to create instance: %s", lcb_strerror(NULL, err));
    }

    Newxz(object, 1, PLCB_t);
    lcb_set_cookie(instance, object);
    object->instance = instance;

    plcb_callbacks_setup(object);
    plcb_vh_callbacks_setup(object);

    #define get_stash_assert(stashname, target) \
        if (! (object->target = gv_stashpv(stashname, 0)) ) { \
            die("Couldn't load '%s'", stashname); \
        }

    get_stash_assert(PLCB_RET_CLASSNAME, ret_stash);
    get_stash_assert(PLCB_COUCH_HANDLE_INFO_CLASSNAME, handle_av_stash);
    get_stash_assert(PLCB_OPCTX_CLASSNAME, opctx_sync_stash);

    blessed_obj = newSV(0);
    sv_setiv(newSVrv(blessed_obj, "Couchbase::Bucket"), PTR2IV(object));

    object->selfobj = SvRV(blessed_obj);
    object->deflctx = new_opctx(object, PLCB_OPCTXf_IMPLICIT);

    return blessed_obj;
}

static int
PLCB_connect(PLCB_t *object)
{
    lcb_error_t err;
    lcb_t instance = object->instance;

    if (object->connected) {
        warn("Already connected");
        return 1;

    } else {
        if ((err = lcb_connect(instance)) != LCB_SUCCESS) {
            goto GT_ERR;
        }
        lcb_wait(instance);
        if ((err = lcb_get_bootstrap_status(instance)) != LCB_SUCCESS) {
            goto GT_ERR;
        }
        object->connected = 1;
        return 1;
    }

    GT_ERR:
    die("Couldn't connect: 0x%x (%s)", err, lcb_strerror(NULL, err));
    return 0;
}

static void
get_converter_pointers(PLCB_t *object, int type, SV ***cv_encode, SV ***cv_decode)
{
    if (type == PLCB_CONVERTERS_CUSTOM) {
        *cv_encode = &object->cv_customenc;
        *cv_decode = &object->cv_customdec;
    } else if (type == PLCB_CONVERTERS_JSON) {
        *cv_encode = &object->cv_jsonenc;
        *cv_decode = &object->cv_jsondec;
    } else if (type == PLCB_CONVERTERS_STORABLE) {
        *cv_encode = &object->cv_serialize;
        *cv_decode = &object->cv_deserialize;
    } else {
        die("Unrecognized converter type %d", type);
    }
}

static void
PLCB__set_converters(PLCB_t *object, int type, CV *encode, CV *decode)
{
    SV **cv_encode, **cv_decode;
    get_converter_pointers(object, type, &cv_encode, &cv_decode);
    if (*cv_encode) {
        SvREFCNT_dec(*cv_encode);
    }
    if (*cv_decode) {
        SvREFCNT_dec(*cv_decode);
    }
    SvREFCNT_inc(encode);
    SvREFCNT_inc(decode);
    *cv_encode = (SV*)encode;
    *cv_decode = (SV*)decode;
}

static SV *
PLCB__get_converters(PLCB_t *object, int type)
{
    SV **cv_encode, **cv_decode;
    SV *my_encode, *my_decode;
    AV *ret;
    get_converter_pointers(object, type, &cv_encode, &cv_decode);
    if ((my_encode = *cv_encode)) {
        my_encode = newRV_inc(my_encode);
    } else {
        my_encode = &PL_sv_undef; SvREFCNT_inc(my_encode);
    }
    if ((my_decode = *cv_decode)) {
        my_decode = newRV_inc(my_decode);
    } else {
        my_decode = &PL_sv_undef; SvREFCNT_inc(my_decode);
    }
    ret = newAV();
    av_push(ret, my_encode);
    av_push(ret, my_decode);
    return newRV_noinc((SV*)ret);
}

/* lcb_cntl() APIs */
static void
PLCB__cntl_set(PLCB_t *object, int setting, int type, SV *value)
{
    lcb_error_t err;
    void *p = NULL;
    union {
        float floatval;
        int intval;
        unsigned uintval;
        size_t sizeval;
        uint32_t u32val;
    } u;
    p = &u;

    if (!SvOK(value)) {
        die("Passed empty value");
    }

    if (type == PLCB_SETTING_INT) {
        u.intval = SvIV(value);
    } else if (type == PLCB_SETTING_UINT) {
        u.uintval = SvUV(value);
    } else if (type == PLCB_SETTING_U32) {
        u.u32val = SvUV(value);
    } else if (type == PLCB_SETTING_SIZE) {
        u.sizeval = SvUV(value);
    } else if (type == PLCB_SETTING_TIMEOUT) {
        u.u32val = SvNV(value) * 1000000;
    } else if (type == PLCB_SETTING_STRING) {
        p = SvPV_nolen(value);
    } else {
        die("Unrecognized type code %d", type);
    }
    err = lcb_cntl(object->instance, LCB_CNTL_SET, setting, p);
    if (err != LCB_SUCCESS) {
        warn("Failed to set setting=%d, type=%d", setting, type);
    }
}

static SV *
PLCB__cntl_get(PLCB_t *object, int setting, int type)
{
    lcb_error_t err;
    void *p = NULL;
    union {
        float floatval;
        int intval;
        unsigned uintval;
        size_t sizeval;
        uint32_t u32val;
        const char *strval;
    } u;

    err = lcb_cntl(object->instance, LCB_CNTL_GET, setting, &u);
    if (err != LCB_SUCCESS) {
        warn("Couldn't set setting=%d, type=%d: %s", setting, type, lcb_strerror(NULL, err));
        SvREFCNT_inc(&PL_sv_undef);
        return &PL_sv_undef;
    }

    if (type == PLCB_SETTING_INT) {
        return newSViv(u.intval);
    } else if (type == PLCB_SETTING_UINT) {
        return newSVuv(u.uintval);
    } else if (type == PLCB_SETTING_U32) {
        return newSVuv(u.u32val);
    } else if (type == PLCB_SETTING_SIZE) {
        return newSVuv(u.sizeval);
    } else if (type == PLCB_SETTING_TIMEOUT) {
        return newSVnv((float)u.u32val / 1000000.0);
    } else if (type == PLCB_SETTING_STRING) {
        return newSVpvn(u.strval, 0);
    } else {
        die("Unknown type %d", type);
        return NULL;
    }
}

static void
init_singleop(plcb_SINGLEOP *so, PLCB_t *parent, SV *doc, SV *ctx, SV *options)
{
    if (!plcb_doc_isa(parent, doc)) {
        sv_dump(doc);
        die("Must pass a Couchbase::Document");
        /* Initialize the document to 0 */
    }

    so->docav = (AV *)SvRV(doc);
    so->opctx = ctx;
    so->parent = parent;

    plcb_doc_set_err(parent, so->docav, -1);

    if (options && SvTYPE(options) != SVt_NULL) {
        if (SvROK(options) == 0 || SvTYPE(SvRV(options)) != SVt_PVHV) {
            sv_dump(options);
            die("options must be undef or a HASH reference");
        }
        so->cmdopts = options;
    }

    if (ctx != &PL_sv_undef) {
        if (!plcb_opctx_isa(parent, ctx)) {
            die("ctx must be undef or a Couchbase::OpContext object");
        }
        if (parent->curctx && SvRV(ctx) != SvRV(parent->curctx)) {
            sv_dump(parent->curctx);
            sv_dump(ctx);
            die("Current context already set!");
        }
        so->opctx = ctx;
    } else {
        if (parent->curctx && SvRV(parent->curctx) != SvRV(ctx)) {
            /* Have a current context? */
            warn("Existing batch context found. This may leak memory.");
            lcb_sched_fail(parent->instance);
            clear_opctx(parent);
        }

        so->opctx = parent->deflctx;
        lcb_sched_enter(parent->instance);
    }
}

SV *
PLCB_args_return(plcb_SINGLEOP *so, lcb_error_t err)
{
    /* Figure out what type of context we are */
    plcb_OPCTX *ctx = NUM2PTR(plcb_OPCTX*, SvIV(SvRV(so->opctx)));

    if (err != LCB_SUCCESS) {
        /* Remove the doc's "Parent" field */
        av_store(so->docav, PLCB_RETIDX_PARENT, &PL_sv_undef);

        if (ctx->flags & PLCB_OPCTXf_IMPLICIT) {
            lcb_sched_fail(so->parent->instance);
        }

        die("Couldn't schedule operation. Code 0x%x (%s)\n", err, lcb_strerror(NULL, err));
        return NULL;
    }

    /* Increment refcount for the parent */
    av_store(so->docav, PLCB_RETIDX_PARENT, newRV_inc(SvRV(so->opctx)));

    /* Increment refcount for the doc itself (decremented in callback) */
    SvREFCNT_inc((SV*)so->docav);

    /* Increment remaining count on the context */
    ctx->nremaining++;

    if (ctx->flags & PLCB_OPCTXf_IMPLICIT) {
        lcb_sched_leave(so->parent->instance);
        lcb_wait3(so->parent->instance, LCB_WAIT_NOCHECK);
    }

    SvREFCNT_inc(&PL_sv_undef);
    return &PL_sv_undef;
}

#define dPLCB_INPUTS \
    SV *options = &PL_sv_undef; SV *ctx = &PL_sv_undef;

#define FILL_EXTRA_PARAMS() \
    if (items > 4) { croak_xs_usage(cv, "bucket, doc [, options, ctx ]"); } \
    if (items >= 3) { options = ST(2); } \
    if (items >= 4) { ctx = ST(3); }

MODULE = Couchbase PACKAGE = Couchbase::Bucket    PREFIX = PLCB_

PROTOTYPES: DISABLE

SV *
PLCB_construct(const char *pkg, HV *options)

int
PLCB_connect(PLCB_t *object)

void
PLCB__set_converters(PLCB_t *object, int type, CV *encode, CV *decode)

void
PLCB__cntl_set(PLCB_t *object, int setting, int type, SV *value)

SV *
PLCB__cntl_get(PLCB_t *object, int setting, int type)

void
PLCB_DESTROY(PLCB_t *object)
    CODE:
    plcb_cleanup(object);
    Safefree(object);

SV *
PLCB_get(PLCB_t *self, SV *doc, ...)
    PREINIT:
    plcb_SINGLEOP opinfo = { PLCB_CMD_GET };
    dPLCB_INPUTS

    CODE:
    FILL_EXTRA_PARAMS()

    init_singleop(&opinfo, self, doc, ctx, options);
    RETVAL = PLCB_op_get(self, &opinfo);
    OUTPUT: RETVAL
    
SV *
PLCB__store(PLCB_t *self, SV *doc, ...)
    ALIAS:
    upsert = PLCB_CMD_SET
    insert = PLCB_CMD_ADD
    replace = PLCB_CMD_REPLACE

    PREINIT:
    plcb_SINGLEOP opinfo = { 0 };
    dPLCB_INPUTS
    
    CODE:
    FILL_EXTRA_PARAMS()
    opinfo.cmdbase = ix;
    init_singleop(&opinfo, self, doc, ctx, options);

    
    RETVAL = PLCB_op_set(self, &opinfo);
    OUTPUT: RETVAL
    
SV *
PLCB_remove(PLCB_t *self, SV *doc, ...)
    PREINIT:
    plcb_SINGLEOP opinfo = { PLCB_CMD_REMOVE };
    dPLCB_INPUTS

    CODE:
    FILL_EXTRA_PARAMS()
    init_singleop(&opinfo, self, doc, ctx, options);
    
    RETVAL = PLCB_op_remove(self, &opinfo);
    OUTPUT: RETVAL

SV *
PLCB_cluster_nodes(PLCB_t *object)
    PREINIT:
    AV *retav;
    const char * const * server_nodes;

    CODE:
    server_nodes = lcb_get_server_list(object->instance);
    retav = newAV();
    RETVAL = newRV_noinc((SV*)retav);

    if (server_nodes) {
        const char * const *cur_node;
        for (cur_node = server_nodes; *cur_node; cur_node++) {
            av_push(retav, newSVpv(*cur_node, 0));
        }
    }

    OUTPUT: RETVAL
    
SV *
PLCB__new_viewhandle(PLCB_XS_OBJPAIR_t self, stash)
    HV *stash
    
    CODE:
    RETVAL = plcb_vh_new(stash, self.sv, self.ptr);
    OUTPUT: RETVAL


SV *
PLCB_batch(PLCB_t *object)
    PREINIT:
    SV *ctxrv = NULL;

    CODE:
    if (object->curctx) {
        die("Previous context must be cleared explicitly");
    }

    ctxrv = new_opctx(object, 0);
    object->curctx = newRV_inc(SvRV(ctxrv));
    RETVAL = ctxrv;

    lcb_sched_enter(object->instance);
    OUTPUT: RETVAL


void
PLCB__ctx_clear(PLCB_t *object)
    CODE:
    clear_opctx(object);

MODULE = Couchbase PACKAGE = Couchbase::OpContext PREFIX = PLCB_ctx_

void
PLCB_ctx_wait_all(plcb_OPCTX *ctx)
    PREINIT:
    PLCB_t *parent;

    CODE:
    if (!parent) {
        die("Parent context is destroyed");
    }

    if (!parent->curctx) {
        die("Current context is not active");
    }

    if (!ctx->nremaining) {
        return;
    }
    /* Remove the 'wait_one' flag */
    ctx->flags &= ~PLCB_OPCTXf_WAITONE;
    lcb_sched_leave(parent->instance);
    lcb_wait3(parent->instance, LCB_WAIT_NOCHECK);
    clear_opctx(parent);


SV *
PLCB_ctx_wait_one(plcb_OPCTX *ctx)
    PREINIT:
    PLCB_t *parent;

    CODE:
    if (!parent) {
        die("Parent context is destroyed");
    }

    if (ctx->ctxqueue) {
        RETVAL = av_shift(ctx->ctxqueue);
        if (RETVAL != &PL_sv_undef) {
            goto GT_DONE;
        }
    }

    if (!parent->curctx) {
        die("Current context is not active");
    }

    if (!ctx->nremaining) {
        clear_opctx(parent);
        RETVAL = &PL_sv_undef;
        SvREFCNT_inc(&PL_sv_undef);
        goto GT_DONE;
    }
    if (!ctx->ctxqueue) {
        ctx->ctxqueue = newAV();
    }
    ctx->flags |= PLCB_OPCTXf_WAITONE;
    lcb_sched_leave(parent->instance);
    lcb_wait3(parent->instance, LCB_WAIT_NOCHECK);
    RETVAL = av_shift(ctx->ctxqueue);

    GT_DONE: ;
    OUTPUT: RETVAL

SV *
PLCB_ctx__cbo(plcb_OPCTX *ctx)
    PREINIT:
    PLCB_t *parent;
    CODE:
    (void)parent;
    RETVAL = newRV_inc(SvRV(ctx->parent));
    OUTPUT: RETVAL

void
PLCB_ctx_DESTROY(plcb_OPCTX *ctx)
    PREINIT:
    PLCB_t *parent;
    CODE:
    SvREFCNT_dec(ctx->parent);
    SvREFCNT_dec(ctx->ctxqueue);

MODULE = Couchbase PACKAGE = Couchbase    PREFIX = PLCB_

HV *
PLCB_lcb_version()
    PREINIT:
    lcb_U32 ivers;
    HV *ret;
    const char *tmp;

    CODE:
    ret = newHV();
    tmp = lcb_get_version(&ivers);
    
    hv_stores(ret, "hex", newSVuv(ivers));
    hv_stores(ret, "str", newSVpv(tmp, 0));
    if (lcb_cntl(NULL, LCB_CNTL_GET, LCB_CNTL_CHANGESET, &tmp) == LCB_SUCCESS) {
        hv_stores(ret, "rev", newSVpv(tmp, 0));
    }
    
    RETVAL = ret;
    OUTPUT: RETVAL

IV
PLCB__get_errtype(int code)
    CODE:
    RETVAL = lcb_get_errtype(code);
    OUTPUT: RETVAL


BOOT:
/*XXX: DO NOT MODIFY WHITESPACE HERE. xsubpp is touchy*/
#define PLCB_BOOTSTRAP_DEPENDENCY(bootfunc) \
PUSHMARK(SP); \
mXPUSHs(newSVpv("Couchbase", sizeof("Couchbase")-1)); \
mXPUSHs(newSVpv(XS_VERSION, sizeof(XS_VERSION)-1)); \
PUTBACK; \
bootfunc(aTHX_ cv); \
SPAGAIN;
{
    PLCB_BOOTSTRAP_DEPENDENCY(boot_Couchbase__View)
}
#undef PLCB_BOOTSTRAP_DEPENDENCY
