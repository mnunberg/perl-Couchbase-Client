#include "perl-couchbase.h"
#include "plcb-util.h"
#include "plcb-commands.h"

static int PLCB_connect(SV* self);

void plcb_cleanup(PLCB_t *object)
{
    if (object->instance) {
        lcb_destroy(object->instance);
        object->instance = NULL;
    }

#define _free_cv(fld) if (object->fld) { SvREFCNT_dec(object->fld); object->fld = NULL; }
    _free_cv(cv_compress); _free_cv(cv_decompress);
    _free_cv(cv_serialize); _free_cv(cv_deserialize);
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
        PLCB_connect(blessed_obj);
    }

    return blessed_obj;
}


#define mk_instance_vars(sv, inst_name, obj_name) \
    if (!SvROK(sv)) { die("self must be a reference"); } \
    obj_name = NUM2PTR(PLCB_t*, SvIV(SvRV(sv))); \
    if (!obj_name) { die("tried to access de-initialized PLCB_t"); } \
    inst_name = obj_name->instance;

static int PLCB_connect(SV *self)
{
    lcb_t instance;
    lcb_error_t err;
    PLCB_t *object;

    mk_instance_vars(self, instance, object);

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

/*used for settings accessors*/
enum {
    SETTINGS_ALIAS_BASE,
    SETTINGS_ALIAS_COMPRESS,
    SETTINGS_ALIAS_COMPRESS_COMPAT,
    SETTINGS_ALIAS_SERIALIZE,
    SETTINGS_ALIAS_CONVERT,
    SETTINGS_ALIAS_DECONVERT,
    SETTINGS_ALIAS_COMP_THRESHOLD,
    SETTINGS_ALIAS_DEREF_RVPV
};

MODULE = Couchbase PACKAGE = Couchbase::Bucket    PREFIX = PLCB_

PROTOTYPES: DISABLE

SV *
PLCB_construct(pkg, options)
    const char *pkg
    AV *options

void
PLCB_DESTROY(self)
    SV *self

    CODE:
    PLCB_t *object;
    lcb_t instance;

    mk_instance_vars(self, instance, object);
    plcb_cleanup(object);
    Safefree(object);

    PERL_UNUSED_VAR(instance);
    
SV *
PLCB_get(self, key, ...)
    SV *self
    SV *key
    
    CODE:
    PLCB_args_t args = { PLCB_CMD_SINGLE_GET };
    PLCB_ARGS_FROM_STACK(2, &args, "get(key, options");
    args.keys = key;

    RETVAL = PLCB_op_get(self, &args);
    OUTPUT: RETVAL
    
SV *
PLCB_get_multi(self, keys, ...)
    SV *self
    SV *keys
    CODE:
    PLCB_args_t args = {PLCB_CMD_MULTI_GET};
    PLCB_ARGS_FROM_STACK(2, &args, "get_multi(keys, options)");
    args.keys = keys;
    
    RETVAL = PLCB_op_get(self, &args);
    OUTPUT: RETVAL
    
SV *
PLCB__store(self, key, value, ...)
    SV *self
    SV *key
    SV *value
    
    ALIAS:
    upsert = PLCB_CMD_SINGLE_SET
    insert = PLCB_CMD_SINGLE_ADD
    update = PLCB_CMD_SINGLE_REPLACE
    
    CODE:
    PLCB_args_t args = { 0 };
    PLCB_ARGS_FROM_STACK(3, &args, "store(key, value, options)");
    args.cmd = ix;
    args.keys = key;
    args.value = value;
    
    RETVAL = PLCB_op_set(self, &args);
    OUTPUT: RETVAL

SV *
PLCB__store_multi(self, kv, ...)
    SV *self
    SV *kv
    
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
PLCB_remove(self, key, ...)
    SV *self
    SV *key
    
    CODE:
    PLCB_args_t args = { PLCB_CMD_SINGLE_REMOVE };
    PLCB_ARGS_FROM_STACK(2, &args, "remove(key, options)");
    args.keys = key;
    
    RETVAL = PLCB_op_remove(self, &args);
    OUTPUT: RETVAL
    
SV *
PLCB_remove_multi(self, keys, ...)
    SV *self
    SV *keys
    
    CODE:
    PLCB_args_t args = { PLCB_CMD_MULTI_REMOVE };
    PLCB_ARGS_FROM_STACK(2, &args, "remove_multi(keys, options)");
    args.keys = keys;
    
    RETVAL = PLCB_op_remove(self, &args);
    OUTPUT: RETVAL


    
IV
PLCB__settings(self, ...)
    SV *self

    ALIAS:
    enable_compress             = SETTINGS_ALIAS_COMPRESS_COMPAT
    compression_settings        = SETTINGS_ALIAS_COMPRESS
    serialization_settings      = SETTINGS_ALIAS_SERIALIZE
    conversion_settings         = SETTINGS_ALIAS_CONVERT
    deconversion_settings       = SETTINGS_ALIAS_DECONVERT
    compress_threshold          = SETTINGS_ALIAS_COMP_THRESHOLD
    dereference_scalar_ref_settings  = SETTINGS_ALIAS_DEREF_RVPV

    PREINIT:
    int flag = 0;
    int new_value = 0;
    lcb_t instance;
    PLCB_t *object;

    CODE:
    mk_instance_vars(self, instance, object);
    switch (ix) {
        case SETTINGS_ALIAS_COMPRESS:
        case SETTINGS_ALIAS_COMPRESS_COMPAT:
            flag = PLCBf_USE_COMPRESSION;
            break;

        case SETTINGS_ALIAS_SERIALIZE:
            flag = PLCBf_USE_STORABLE;
            break;

        case SETTINGS_ALIAS_CONVERT:
            flag = PLCBf_USE_STORABLE|PLCBf_USE_COMPRESSION;
            break;

        case SETTINGS_ALIAS_DECONVERT:
            flag = PLCBf_DECONVERT;
            break;

        case SETTINGS_ALIAS_COMP_THRESHOLD:
            flag = PLCBf_COMPRESS_THRESHOLD;
            break;

        case SETTINGS_ALIAS_DEREF_RVPV:
            flag = PLCBf_DEREF_RVPV;
            break;

        case 0:
            die("This function should not be called directly. "
                "use one of its aliases");

        default:
            die("Wtf?");
            break;
    }

    if (items == 2) {
        new_value = sv_2bool(ST(1));

    } else if (items == 1) {
        new_value = -1;

    } else {
        die("%s(self, [value])", GvNAME(GvCV(cv)));
    }

    if (!SvROK(self)) {
        die("%s: I was given a bad object", GvNAME(GvCV(cv)));
    }


    RETVAL = plcb_convert_settings(object, flag, new_value);
    //warn("Report flag %d = %d", flag, RETVAL);

    PERL_UNUSED_VAR(instance);

    OUTPUT: RETVAL


NV
PLCB_timeout(self, ...)
    SV *self

    PREINIT:
    NV new_param;
    uint32_t usecs;
    NV ret;

    lcb_t instance;
    PLCB_t *object;

    CODE:

    mk_instance_vars(self, instance, object);
    ret = lcb_cntl_getu32(instance, LCB_CNTL_OP_TIMEOUT) / (1000*1000);

    if (items == 2) {
        new_param = SvNV(ST(1));
        if (new_param <= 0) {
            warn("Cannot disable timeouts.");
            XSRETURN_UNDEF;
        }

        usecs = new_param * (1000*1000);
        lcb_cntl_setu32(instance, LCB_CNTL_OP_TIMEOUT, usecs);
    }

    RETVAL = ret;

    OUTPUT:
    RETVAL

SV *
PLCB_cluster_nodes(self)
    SV *self
    PREINIT:
    lcb_t instance;
    PLCB_t *object;
    AV *retav;
    const char * const * server_nodes;

    CODE:
    mk_instance_vars(self, instance, object);
    server_nodes = lcb_get_server_list(instance);
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
PLCB_connect(self)
    SV *self

MODULE = Couchbase PACKAGE = Couchbase    PREFIX = PLCB_

SV *
PLCB_lcb_version()
    PREINIT:
    uint32_t iversion = 0;
    const char *strversion;
    const char *changeset;
    lcb_error_t err;
    AV *ret;

    CODE:
    strversion = lcb_get_version(&iversion);
    ret = newAV();
    av_store(ret, 0, newSVpv(strversion, 0));
    av_store(ret, 1, newSVuv(iversion));
    err = lcb_cntl(NULL, LCB_CNTL_GET, LCB_CNTL_CHANGESET, &changeset);
    if (err == LCB_SUCCESS) {
        av_store(ret, 2, newSVpv(changeset, 0));
    } else {
        warn("Couldn't retrieve changeset from library. %s", lcb_strerror(NULL, err));
    }
    
    RETVAL = newRV_noinc((SV*)ret);
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
    {
        lcb_uint32_t cbc_version = 0;
        const char *cbc_version_string;
        cbc_version_string = lcb_get_version(&cbc_version);
        /*
        warn("Couchbase library version is (%s) %x",
             cbc_version_string, cbc_version);
        */
        PERL_UNUSED_VAR(cbc_version_string);
    }
    PLCB_BOOTSTRAP_DEPENDENCY(boot_Couchbase__View)
}
#undef PLCB_BOOTSTRAP_DEPENDENCY