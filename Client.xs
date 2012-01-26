#include "perl-couchbase.h"
#include "plcb-util.h"


//#define libcouchbase_wait(x) \
//	libcouchbase_flush_buffers(x, NULL);

#define libcouchbase_behavior_set_syncmode(x, y)

static void PLCB_cleanup(PLCB_t *object)
{
    if(object->instance) {
        libcouchbase_destroy(object->instance);
        object->instance = NULL;
    }
    if(object->errors) {
        SvREFCNT_dec(object->errors);
        object->errors = NULL;
    }
#define _free_cv(fld) \
    if(object->fld) { \
        SvREFCNT_dec(object->fld); object->fld = NULL; \
}
    _free_cv(cv_compress); _free_cv(cv_decompress);
    _free_cv(cv_serialize); _free_cv(cv_deserialize);
#undef _free_cv
    
}

/*Construct a new libcouchbase object*/
SV *PLCB_construct(const char *pkg, AV *options)
{
    libcouchbase_t instance;
    libcouchbase_error_t oprc;
    SV *blessed_obj;
    PLCB_t *object;
    
    char *host = NULL, *username = NULL, *password = NULL, *bucket = NULL;
    
    plcb_ctor_cbc_opts(options,
                         &host, &username, &password, &bucket);
        
    instance = libcouchbase_create(host, username, password, bucket, NULL);    
    
    if(!instance) {
        die("Failed to create instance");
    }
    
    Newxz(object, 1, PLCB_t);
    
    plcb_ctor_conversion_opts(object, options);
    plcb_ctor_init_common(object, instance);
	
    libcouchbase_set_cookie(instance, object);
	libcouchbase_behavior_set_syncmode(instance, LIBCOUCHBASE_SYNCHRONOUS);
    
    if(libcouchbase_connect(instance) == LIBCOUCHBASE_SUCCESS) {
        libcouchbase_wait(instance);
		warn("Connected!");
    }
    
    plcb_setup_callbacks(object);
    
    blessed_obj = newSV(0);
    sv_setiv(newSVrv(blessed_obj, "Couchbase::Client"), PTR2IV(object));
    return blessed_obj;
}

#define mk_instance_vars(sv, inst_name, obj_name) \
    if(!SvROK(sv)) { die("self must be a reference"); } \
    obj_name = NUM2PTR(PLCB_t*, SvIV(SvRV(sv))); \
    if(!obj_name) { die("tried to access de-initialized PLCB_t"); } \
    inst_name = obj_name->instance;

#define bless_return(object, rv, av) \
	return plcb_ret_blessed_rv(object, av);


static SV *PLCB_set_common(SV *self,
    SV *key, SV *value,
    int storop,
    int exp_offset, uint64_t cas)
{
    libcouchbase_t instance;
    PLCB_t *object;
    libcouchbase_error_t err;
    STRLEN klen = 0, vlen = 0;
    char *skey, *sval;
    PLCB_sync_t *syncp;
    AV *ret_av;
    SV *ret_rv;
    time_t exp;
    uint32_t store_flags = 0;
    
    mk_instance_vars(self, instance, object);
        
    plcb_get_str_or_die(key, skey, klen, "Key");
    plcb_get_str_or_die(value, sval, vlen, "Value");
    
    syncp = &(object->sync);
    plcb_sync_initialize(syncp, self, skey, klen);
    
    
    /*Clear existing error status first*/
    av_clear(object->errors);
    ret_av = newAV();
    
    exp = exp_offset ? time(NULL) + exp_offset : 0;
    
    plcb_convert_storage(object, &value, &vlen, &store_flags);
    err = libcouchbase_store(instance, syncp, storop,
        skey, klen, SvPVX(value), vlen, store_flags, exp, cas);
    plcb_convert_storage_free(object, value, store_flags);
    
    if(err != LIBCOUCHBASE_SUCCESS) {
        plcb_ret_set_err(object, ret_av, err);
    } else {
        warn("Waiting..");
        libcouchbase_wait(instance);
        warn("Done!");
        plcb_ret_set_err(object, ret_av, syncp->err);
    }
    bless_return(object, ret_rv, ret_av);
}

static SV *PLCB_arithmetic_common(SV *self,
    SV *key, int64_t delta,
    int do_create, uint64_t initial,
    int exp_offset)
{
    PLCB_t *object;
    libcouchbase_t instance;

    char *skey;
    SV *ret_rv;
    AV *ret_av;
    
    STRLEN nkey;
    
    PLCB_sync_t *syncp;
    time_t exp;
    libcouchbase_error_t err;
    
    mk_instance_vars(self, instance, object);
    exp = exp_offset ? time(NULL) + exp_offset : 0;
    
    plcb_get_str_or_die(key, skey, nkey, "Key");
        
    syncp = &(object->sync);
    plcb_sync_initialize(syncp, self, skey, nkey);
    ret_av = newAV();
    
    err = libcouchbase_arithmetic(
        instance, syncp, skey, nkey, delta,
        exp, do_create, initial
    );
    if(err != LIBCOUCHBASE_SUCCESS) {
		plcb_ret_set_err(object, ret_av, err);
    } else {
        if(!syncp->received) {
            libcouchbase_wait(instance);
        }
        plcb_ret_set_err(object, ret_av, syncp->err);
		
        if(syncp->err == LIBCOUCHBASE_SUCCESS) {
            plcb_ret_set_numval(object, ret_av, syncp->arithmetic, syncp->cas);
        }
    }
    bless_return(object, ret_rv, ret_av);
}

static SV *PLCB_get_common(SV *self, SV *key, int exp_offset)
{
    libcouchbase_t instance;
    PLCB_t *object;
    PLCB_sync_t *syncp;
    libcouchbase_error_t err;    
    STRLEN klen;
    char *skey;
    AV *ret_av;
    SV *ret_rv;
    
    time_t exp;
    time_t *exp_arg;
    
    mk_instance_vars(self, instance, object);
    plcb_get_str_or_die(key, skey, klen, "Key");
    
    ret_av = newAV();
    syncp = &(object->sync);
    plcb_sync_initialize(syncp, self, skey, klen);
    av_clear(object->errors);
   
    if(exp_offset) {
        exp = time(NULL) + exp_offset;
        exp_arg = &exp;
    } else {
        exp_arg = NULL;
    }
    err = libcouchbase_mget(instance, syncp, 1,
                            (const void * const*)&skey, &klen,
                            exp_arg);
    
    if(err != LIBCOUCHBASE_SUCCESS) {
		plcb_ret_set_err(object, ret_av, err);
    } else {
        libcouchbase_wait(instance);
		plcb_ret_set_err(object, ret_av, syncp->err);
		if(syncp->err == LIBCOUCHBASE_SUCCESS) {
            plcb_ret_set_strval(
                object, ret_av, syncp->value, syncp->nvalue,
                syncp->store_flags, syncp->cas);
        }
    }
    bless_return(object, ret_rv, ret_av);
}

SV *PLCB_get_errors(SV *self)
{
    libcouchbase_t instance;
    PLCB_t *object;
    AV *errors;
    
    mk_instance_vars(self, instance, object);
    return newRV_inc((SV*)object->errors);
}

#define set_plst_get_offset(exp_idx, exp_var, diemsg) \
    if(items == (exp_idx - 1)) { \
        exp_var = 0; \
     } else if(items == exp_idx) { \
        if(!SvIOK(ST(exp_idx-1))) { \
            sv_dump(ST(exp_idx-1)); \
            die("Expected numeric argument"); \
        } \
        exp_var = SvIV(ST((exp_idx-1))); \
    } else { \
        die(diemsg); \
    }

/*variable length ->get and ->cas are in the XS section*/


SV *PLCB_get(SV *self, SV *key)
{
    return PLCB_get_common(self, key, 0);
}

SV *PLCB_touch(SV *self, SV *key, UV exp_offset)
{
    return PLCB_get_common(self, key, exp_offset);
}

SV *PLCB_remove(SV *self, SV *key, uint64_t cas)
{
    libcouchbase_t instance;
    PLCB_t *object;
    libcouchbase_error_t err;
    
    char *skey;
    AV *ret_av;
    SV *ret_rv;
    STRLEN key_len;
    PLCB_sync_t *syncp;
    
    mk_instance_vars(self, instance, object);
    
    plcb_get_str_or_die(key, skey, key_len, "Key");
    ret_av = newAV();
    av_clear(object->errors);
    
    syncp = &(object->sync);
    plcb_sync_initialize(syncp, self, skey, key_len);
    
    if( (err = libcouchbase_remove(instance, syncp, skey, key_len, cas))
       != LIBCOUCHBASE_SUCCESS) {
		plcb_ret_set_err(object, ret_av, err);
    } else {
        libcouchbase_wait(instance);
		plcb_ret_set_err(object, ret_av, syncp->err);
    }
    bless_return(object, ret_rv, ret_av);
}

SV *PLCB_stats(SV *self, AV *stats)
{
    libcouchbase_t instance;
    PLCB_t *object;
    char *skey;
    STRLEN nkey;
    int curidx;
    libcouchbase_error_t err;
    
    SV *ret_hvref;
    SV **tmpsv;
    
    mk_instance_vars(self, instance, object);
    if(object->stats_hv) {
        die("Hrrm.. stats_hv should be NULL");
    }
    
    av_clear(object->errors);
    object->stats_hv = newHV();
    ret_hvref = newRV_noinc((SV*)object->stats_hv);
    
    if(stats == NULL || (curidx = av_len(stats)) == -1) {
        skey = NULL;
        nkey = 0;
        curidx = -1;
        err = libcouchbase_server_stats(instance, NULL, NULL, 0);
        if(err != LIBCOUCHBASE_SUCCESS) {
            SvREFCNT_dec(ret_hvref);
            ret_hvref = &PL_sv_undef;
        }
        libcouchbase_wait(instance);
    } else {
        for(; curidx >= 0; curidx--) {
            tmpsv = av_fetch(stats, curidx, 0);
            if(tmpsv == NULL
               || SvTYPE(*tmpsv) == SVt_NULL
               || (!SvPOK(*tmpsv))) {
                continue;
            }
            skey = SvPV(*tmpsv, nkey);
            err = libcouchbase_server_stats(instance, NULL, skey, nkey);
            if(err == LIBCOUCHBASE_SUCCESS) {
                libcouchbase_wait(instance);
            }
        }
    }
    
    object->stats_hv = NULL;
    return ret_hvref;
}

/*Used for set/get/replace/add common interface*/
static libcouchbase_storage_t PLCB_XS_setmap[] = {
    LIBCOUCHBASE_SET,
    LIBCOUCHBASE_ADD,
    LIBCOUCHBASE_REPLACE,
    LIBCOUCHBASE_APPEND,
    LIBCOUCHBASE_PREPEND,
};

MODULE = Couchbase::Client PACKAGE = Couchbase::Client    PREFIX = PLCB_

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
    libcouchbase_t instance;
    mk_instance_vars(self, instance, object);
    PLCB_cleanup(object);
    
    
SV *
PLCB_get(self, key)
    SV *    self
    SV *    key
    

SV *
PLCB_touch(self, key, exp_offset)
    SV *self
    SV *key
    UV exp_offset;

SV *
PLCB_set(self, key, value, ...)
    SV *self
    SV *key
    SV *value
    
    ALIAS:
    add         = 1
    replace     = 2
    append      = 3
    prepend     = 4
    
    PREINIT:
    UV exp_offset;
    
    CODE:
    set_plst_get_offset(4, exp_offset, "USAGE: set(key, value [,expiry]");
    
    RETVAL = PLCB_set_common(
        self, key, value,
        PLCB_XS_setmap[ix],
        exp_offset, 0);
    
    OUTPUT:
    RETVAL
    
    
SV *
PLCB_arithmetic(self, key, ...)
    SV *self
    SV *key
    
    ALIAS:
    incr        = 1
    decr        = 2
    
    PREINIT:
    int64_t delta;
    UV exp_offset;
    SV *initial;
    SV *delta_sv;
    int do_create;
    uint64_t initial_i;
    
    CODE:
    do_create     = 0;
    exp_offset     = 0;
    initial_i     = 0;
    initial     = NULL;
    delta_sv    = NULL;
    
    
    if(items > 2) {
        delta_sv = ST(2);
    }
    
    if(ix == 0) {
        if(items < 4 || items > 5) {
            die("arithmetic(key, delta, initial [,expiry])");
        }
        
        if(SvTYPE( (initial=ST(3)) ) == SVt_NULL) {
            do_create = 0;
        } else {
            do_create = 1;
            initial_i = plcb_sv_to_u64(initial);
        }
        
        if(items == 5 && (exp_offset = SvUV( ST(4) )) == 0 ) {
            die("Expiry offset cannot be 0");
        }
        delta = plcb_sv_to_64(delta_sv);
    } else {
        if(items < 2 || items > 3) {
            die("Usage: incr/decr(key [,delta])");
        }
        delta = (delta_sv) ? plcb_sv_to_64(delta_sv) : 1;
        delta = (ix == 2) ? -delta : delta;
    }

    RETVAL = PLCB_arithmetic_common(
        self, key, delta, do_create, initial_i, exp_offset);
    
    OUTPUT:
    RETVAL


SV *
PLCB_cas(self, key, value, cas_sv, ...)
    SV *self
    SV *key
    SV *value
    SV *cas_sv
    
    PREINIT:
    UV exp_offset;
    uint64_t *cas_val;
    STRLEN cas_len;
    
    CODE:
    plcb_cas_from_sv(cas_sv, cas_val, cas_len);
    
    set_plst_get_offset(5, exp_offset, "USAGE: cas(key,value,cas[,expiry])");
    RETVAL = PLCB_set_common(
        self, key, value,
        LIBCOUCHBASE_SET,
        exp_offset, *cas_val);
    
    OUTPUT:
    RETVAL


SV *
PLCB_remove(self, key, ...)
    SV *self
    SV *key
    
    ALIAS:
    delete = 1
    
    PREINIT:
    uint64_t *cas_ptr;
    STRLEN cas_len;
    SV *cas_sv;
    
    CODE:
    if(items == 2) {
        RETVAL = PLCB_remove(self, key, 0);
    } else {
        cas_sv = ST(2);
        plcb_cas_from_sv(cas_sv, cas_ptr, cas_len);
        RETVAL = PLCB_remove(self, key, *cas_ptr);
    }
    
    OUTPUT:
    RETVAL


SV *
PLCB_get_errors(self)
    SV *self


SV *
PLCB_stats(self, ...)
    SV *self
    
    PREINIT:
    SV *klist;
    
    CODE:    
    if( items < 2 ) {
        klist = NULL;
    } else {
        klist = ST(1);
        if(! (SvROK(klist) && SvTYPE(SvRV(klist)) >= SVt_PVAV) ) {
            die("Usage: stats( ['some', 'keys', ...] )");
        }
    }
    RETVAL = PLCB_stats(self, (klist) ? (AV*)SvRV(klist) : NULL);
    
    OUTPUT:
    RETVAL
    
	
INCLUDE: Async.xs