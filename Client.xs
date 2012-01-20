#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "perl-couchbase.h"

/*single structure to determine the value and/or success of the operation*/


PLCB_sync_t global_sync;

static void get_callback(
    libcouchbase_t instance,
    const void *cookie,
    libcouchbase_error_t err,
    const void *key, size_t nkey,
    const void *value, size_t nvalue,
    uint32_t flags, uint64_t cas)
{
	PLCB_sync_t *syncp = plcb_sync_cast(cookie);
	
	syncp->value = value;
	syncp->nvalue = nvalue;
	
	syncp->key = key;
	syncp->nkey = nkey;
	
	syncp->cas = cas;
	syncp->err = err;
}

static void storage_callback(
    libcouchbase_t instance,
    const void *cookie,
    libcouchbase_storage_t op,
    libcouchbase_error_t err,
    const void *key, size_t nkey,
    uint64_t cas) 
{
	PLCB_sync_t *syncp = plcb_sync_cast(cookie);
	syncp->key = key;
	syncp->nkey = nkey;
	
	syncp->cas = cas;
	syncp->err = err;	
}

static void error_callback(
    libcouchbase_t instance,
    libcouchbase_error_t err,
    const char *errinfo) 
{
    PLCB_t *object;
    SV *elem_list[2];
    
    if(err == LIBCOUCHBASE_SUCCESS) {
        return;
    }
    elem_list[0] = newSViv(err);
    if(errinfo) {
        elem_list[1] = newSVpv(errinfo, 0);
    } else {
        elem_list[1] = &PL_sv_undef;
    }
    
    object = (PLCB_t*)libcouchbase_get_cookie(instance);
    av_push(object->errors,
        newRV_noinc((SV*)av_make(2, elem_list))
    );
}

#ifdef PLCB_HAVE_CONNFAIL
static void connfail_callback(
    libcouchbase_t instance,
    int conn_errno,
    const char *hostname,
    const char *port,
    libcouchbase_retry_t *retry_param)
{
    warn("Error in connecting to %s:%s", hostname, port);
    *retry_param = LIBCOUCHBASE_RETRY_BAIL;
}
#endif

static void ret_populate_err(
    AV *ret,
    libcouchbase_t instance,
    libcouchbase_error_t err)
{
    const char *errstr;
    av_store(ret, PLCB_RETIDX_ERRNUM, newSViv(err));
    if(err != LIBCOUCHBASE_SUCCESS) {
        errstr = libcouchbase_strerror(instance, err);
        if(errstr) {
            av_store(ret, PLCB_RETIDX_ERRSTR, newSVpv(errstr, 0));
        }
    }
}

static void ret_populate_sync_value(
    AV *ret,
    PLCB_sync_t *sync)
{
    SV *cas_sv;
    
    if(sync->value) {
        av_store(ret, PLCB_RETIDX_VALUE,
                 newSVpv(sync->value, sync->nvalue));
        
        av_store(ret, PLCB_RETIDX_CAS,
                 newSVpv((char*)(&sync->cas), 8));
    }
}


static inline void extract_ctor_options(
    AV *options, char **hostp, char **userp, char **passp, char **bucketp
) {
    
#define _assign_options(dst, opt_idx, defl) \
if( (tmp = av_fetch(options, opt_idx, 0)) && SvTRUE(*tmp) ) { \
    *dst = SvPV_nolen(*tmp); \
} else { \
    *dst = defl; \
}
    SV **tmp;
    
    _assign_options(hostp, PLCB_CTORIDX_SERVERS, "127.0.0.1:8091");
    _assign_options(userp, PLCB_CTORIDX_USERNAME, NULL);
    _assign_options(passp, PLCB_CTORIDX_PASSWORD, NULL);
    _assign_options(bucketp, PLCB_CTORIDX_BUCKET, "default");
#undef _assign_options

}


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
}

/*Construct a new libcouchbase object*/
SV *PLCB_construct(const char *pkg, AV *options)
{
    libcouchbase_t instance;
    libcouchbase_error_t oprc;
    SV *blessed_obj;
    PLCB_t *object;
    
    char *host = NULL, *username = NULL, *password = NULL, *bucket = NULL;
    
    extract_ctor_options(options,
                         &host, &username, &password, &bucket);
        
    instance = libcouchbase_create(host, username, password, bucket, NULL);    
    
    if(!instance) {
        die("Failed to create instance");
    }
    
    Newxz(object, 1, PLCB_t);
    object->instance = instance;
    object->errors = newAV();
    if(! (object->ret_stash = gv_stashpv(PLCB_RET_CLASSNAME, 0)) ) {
        die("Could not load '%s'", PLCB_RET_CLASSNAME);
    }

    libcouchbase_set_get_callback(instance, get_callback);
    libcouchbase_set_storage_callback(instance, storage_callback);
    libcouchbase_set_error_callback(instance, error_callback);
#ifdef PLCB_HAVE_CONNFAIL
    libcouchbase_set_connfail_callback(instance, connfail_callback);
#endif

    libcouchbase_set_cookie(instance, object);
    
    if(libcouchbase_connect(instance) == LIBCOUCHBASE_SUCCESS) {
        libcouchbase_wait(instance);
    }
    
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
    rv = newRV_noinc((SV*)av); \
    sv_bless(rv, object->ret_stash); \
    return rv;

static SV *PLCB_set_common(SV *self,
    SV *key, SV *value, int exp_offset, uint64_t cas)
{
    libcouchbase_t instance;
    PLCB_t *object;
    libcouchbase_error_t err;
    STRLEN klen = 0, vlen = 0;
    char *skey, *sval;
    PLCB_sync_t *syncp;
    AV *ret_av;
    SV *ret_rv;
    uint32_t store_flags;
    const char *errdesc;
    time_t exp;
    mk_instance_vars(self, instance, object);
    
    skey = SvPV(key, klen);
    sval = SvPV(value, vlen);
    
    if(! (klen && vlen)) {
        die("got key length %d and value length %d. Both must be nonzero",
            klen, vlen);
    }
    
    syncp = &global_sync;
    plcb_sync_initialize(syncp, self, skey, klen);
    
    ret_av = newAV();
    
    /*Clear existing error status first*/
    av_clear(object->errors);
    
    store_flags = 0;
    if(exp_offset) {
        exp = time(NULL) + exp_offset;
    } else {
        exp = 0;
    }
    
    err = libcouchbase_store(instance,&global_sync, LIBCOUCHBASE_SET,
        skey, klen, sval, vlen, store_flags, exp, cas);
    
    if(err != LIBCOUCHBASE_SUCCESS) {
        ret_populate_err(ret_av, instance, err);
    } else {
        libcouchbase_wait(instance);
        ret_populate_err(ret_av, instance, syncp->err);
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
    
    skey = SvPV(key, klen);
    if(!klen) {
        die("I was given a zero-length key");
    }
    
    ret_av = newAV();
    syncp = &global_sync;
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
        ret_populate_err(ret_av, instance, err);
    } else {
        libcouchbase_wait(instance);
        ret_populate_err(ret_av, instance, syncp->err);
        ret_populate_sync_value(ret_av, syncp);
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

MODULE = Couchbase::Client PACKAGE = Couchbase::Client	PREFIX = PLCB_

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
	SV *	self
	SV *	key
    

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
    
    PREINIT:
    UV exp_offset;
    
    CODE:
    set_plst_get_offset(4, exp_offset, "USAGE: set(key, value [,expiry]");
    RETVAL = PLCB_set_common(self, key, value, exp_offset, 0);
    
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
    cas_val = (uint64_t*)SvPV(cas_sv, cas_len);
    if(!cas_val || cas_len != 8) {
        die("Invalid CAS");
    }
    
    set_plst_get_offset(5, exp_offset, "USAGE: cas(key,value,cas[,expiry])");
    RETVAL = PLCB_set_common(self, key, value, exp_offset, *cas_val);
    
    OUTPUT:
    RETVAL


SV *PLCB_get_errors(self)
    SV *self
