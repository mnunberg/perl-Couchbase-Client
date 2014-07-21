#include "perl-couchbase.h"
#include "plcb-util.h"
#include "plcb-commands.h"

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
    get_stash_assert(PLCB_ITER_CLASSNAME, iter_stash);
    get_stash_assert(PLCB_COUCH_HANDLE_INFO_CLASSNAME, handle_av_stash);


    blessed_obj = newSV(0);
    sv_setiv(newSVrv(blessed_obj, "Couchbase::Bucket"), PTR2IV(object));
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
        if ( (err = lcb_connect(instance)) == LCB_SUCCESS) {
            lcb_wait(instance);
            if (lcb_get_bootstrap_status(instance) != LCB_SUCCESS) {
                return 0;
            }

            object->connected = 1;
            return 1;

        } else {
            return 0;
        }
    }
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
        my_decode = &PL_sv_undef; SvREFNCT_inc(my_decode);
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
    }
}

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
PLCB_get(PLCB_t *self, SV *key, ...)    
    CODE:
    PLCB_args_t args = { PLCB_CMD_SINGLE_GET };
    PLCB_ARGS_FROM_STACK(2, &args, "get(doc, options");
    args.keys = key;

    RETVAL = PLCB_op_get(self, &args);
    OUTPUT: RETVAL
    
SV *
PLCB_get_multi(PLCB_t *self, SV *keys, ...)
    CODE:
    PLCB_args_t args = {PLCB_CMD_MULTI_GET};
    PLCB_ARGS_FROM_STACK(2, &args, "get_multi(keys, options)");
    args.keys = keys;
    
    RETVAL = PLCB_op_get(self, &args);
    OUTPUT: RETVAL
    
SV *
PLCB__store(PLCB_t *self, SV *key, ...)
    ALIAS:
    upsert = PLCB_CMD_SINGLE_SET
    insert = PLCB_CMD_SINGLE_ADD
    update = PLCB_CMD_SINGLE_REPLACE
    
    CODE:
    PLCB_args_t args = { 0 };
    PLCB_ARGS_FROM_STACK(2, &args, "store(key, value, options)");

    args.cmd = ix;
    args.keys = key;
    
    RETVAL = PLCB_op_set(self, &args);
    OUTPUT: RETVAL

SV *
PLCB__store_multi(PLCB_t *self, SV *kv, ...)
    ALIAS:
    upsert_multi = PLCB_CMD_MULTI_SET
    insert_multi = PLCB_CMD_MULTI_ADD
    update_multi = PLCB_CMD_MULTI_REPLACE
    
    CODE:
    PLCB_args_t args = { 0 };
    PLCB_ARGS_FROM_STACK(2, &args, "store_multi({kv}, options)");
    args.cmd = ix;
    args.keys = kv;
    
    RETVAL = PLCB_op_set(self, &args);
    OUTPUT: RETVAL
    
SV *
PLCB_remove(PLCB_t *self, SV *key, ...)
    CODE:
    PLCB_args_t args = { PLCB_CMD_SINGLE_REMOVE };
    PLCB_ARGS_FROM_STACK(2, &args, "remove(key, options)");
    args.keys = key;
    
    RETVAL = PLCB_op_remove(self, &args);
    OUTPUT: RETVAL
    
SV *
PLCB_remove_multi(PLCB_t *self, SV *keys, ...)
    CODE:
    PLCB_args_t args = { PLCB_CMD_MULTI_REMOVE };
    PLCB_ARGS_FROM_STACK(2, &args, "remove_multi(keys, options)");
    args.keys = keys;
    
    RETVAL = PLCB_op_remove(self, &args);
    OUTPUT: RETVAL

SV *
PLCB_observe_multi(PLCB_t *self, SV *keys, ...)
    CODE:
    PLCB_args_t args = { PLCB_CMD_MULTI_OBSERVE };
    PLCB_ARGS_FROM_STACK(2, &args, "observe_multi(docs, options)");
    args.keys = keys;
    RETVAL = PLCB_op_observe(self, &args);
    OUTPUT: RETVAL

SV *
PLCB_observe(PLCB_t *self, SV *keys, ...)
    CODE:
    PLCB_args_t args = { PLCB_CMD_SINGLE_OBSERVE };
    PLCB_ARGS_FROM_STACK(2, &args, "observe(key, options)");
    args.keys = keys;
    RETVAL = PLCB_op_observe(self, &args);
    OUTPUT: RETVAL

SV *
PLCB_sync(PLCB_t *self, SV *key, HV *options)
    ALIAS:
    endure = 1

    CODE:
    PLCB_args_t args = { PLCB_CMD_SINGLE_ENDURE };
    args.keys = key;
    args.cmdopts = options;
    RETVAL = PLCB_op_endure(self, &args);
    OUTPUT: RETVAL

SV *
PLCB_sync_multi(PLCB_t *self, SV *kv, HV *options)
    ALIAS:
    endure_multi = 1
    CODE:
    PLCB_args_t args = { PLCB_CMD_MULTI_ENDURE };
    args.keys = kv;
    args.cmdopts = options;
    RETVAL = PLCB_op_endure(self, &args);
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
