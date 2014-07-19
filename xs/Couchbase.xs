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
SV *PLCB_construct(const char *pkg, AV *options)
{
    lcb_t instance;
    lcb_error_t err;
    struct lcb_create_st cr_opts = { 0 };
    SV *blessed_obj;
    PLCB_t *object;

    cr_opts.version = 3;
    plcb_ctor_cbc_opts(options, &cr_opts);
    err = lcb_create(&instance, &cr_opts);

    if (!instance) {
        die("Failed to create instance: %s", lcb_strerror(NULL, err));
    }

    Newxz(object, 1, PLCB_t);

    plcb_ctor_conversion_opts(object, options);
    plcb_ctor_init_common(object, instance, options);

    lcb_set_cookie(instance, object);

    plcb_callbacks_setup(object);
    plcb_couch_callbacks_setup(object);

    blessed_obj = newSV(0);
    sv_setiv(newSVrv(blessed_obj, "Couchbase::Bucket"), PTR2IV(object));

    if ( (object->my_flags & PLCBf_NO_CONNECT) == 0) {
        PLCB_connect(object);
    }

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

MODULE = Couchbase PACKAGE = Couchbase::Bucket    PREFIX = PLCB_

PROTOTYPES: DISABLE

SV *
PLCB_construct(pkg, options)
    const char *pkg
    AV *options

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
    RETVAL = plcb_couch_handle_new(stash, self.sv, self.ptr);
    OUTPUT: RETVAL

int
PLCB_connect(PLCB_t *self)


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