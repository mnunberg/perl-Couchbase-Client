#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "perl-couchbase.h"
//#include <string.h>

void plcb_callback_get(
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
	syncp->store_flags = flags;
}

void plcb_callback_storage(
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

static void arithmetic_callback(
    libcouchbase_t instance, const void *cookie,
    libcouchbase_error_t err, const void *key, size_t nkey,
    uint64_t value, uint64_t cas)
{
    PLCB_sync_t *syncp = plcb_sync_cast(cookie);
    syncp->key = key; syncp->nkey = nkey;
    syncp->cas = cas; syncp->err = err;
    syncp->arithmetic = value;
}


void plcb_callback_error(
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
        newRV_noinc((SV*)av_make(2, elem_list)));
}

#ifdef PLCB_HAVE_CONNFAIL
void plcb_callback_connfail(
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

/*Common callback for key-only operations*/
static void keyop_callback(
    libcouchbase_t instance, const void *cookie,
    libcouchbase_error_t err,
    const void *key, size_t nkey)
{
    plcb_callback_get(instance, cookie, err, key, nkey,
                      NULL, 0, 0, 0);
}

static void stat_callback(
	libcouchbase_t instance, const void *cookie,
	const char *server,
	libcouchbase_error_t err,
	const void *stat_key, size_t nkey,
	const void *bytes, size_t nbytes)
{
	PLCB_t *object;
	SV *server_sv, *data_sv, *key_sv;
	dSP;
	
	
	
	if(! (stat_key || bytes) ) {
		warn("Got all statistics");
		return;
	}
	
	server_sv = newSVpvn(server, strlen(server));
	if(nkey) {
		key_sv = newSVpvn(stat_key, nkey);
		fprintf(stderr, "stat_callback(): ");
		fwrite(stat_key, nkey, 1, stderr);
		fprintf(stderr, "\n");
	} else {
		key_sv = newSVpvn("", 0);
	}
	
	if(nbytes) {
		data_sv = newSVpvn(bytes, nbytes);
	} else {
		data_sv = newSVpvn("", 0);
	}
	
	object = (PLCB_t*)libcouchbase_get_cookie(instance);
	if(!object->stats_hv) {
		die("We have nothing to write our stats to!");
	}
	
	ENTER;
	SAVETMPS;
	
	PUSHMARK(SP);
	XPUSHs(sv_2mortal(newRV_inc((SV*)object->stats_hv)));
	XPUSHs(sv_2mortal(server_sv));
	XPUSHs(sv_2mortal(key_sv));
	XPUSHs(sv_2mortal(data_sv));
	PUTBACK;
	
	call_pv(PLCB_STATS_SUBNAME, G_DISCARD);
	FREETMPS;
	LEAVE;
}

void plcb_setup_callbacks(PLCB_t *object)
{
    libcouchbase_t instance = object->instance;
    libcouchbase_set_get_callback(instance, plcb_callback_get);
    libcouchbase_set_storage_callback(instance, plcb_callback_storage);
    libcouchbase_set_error_callback(instance, plcb_callback_error);
#ifdef PLCB_HAVE_CONNFAIL
    libcouchbase_set_connfail_callback(instance, plcb_callback_connfail);
#endif

    libcouchbase_set_touch_callback(instance, keyop_callback);
    libcouchbase_set_remove_callback(instance, keyop_callback);
    libcouchbase_set_arithmetic_callback(instance, arithmetic_callback);
    libcouchbase_set_stat_callback(instance, stat_callback);
	
    libcouchbase_set_cookie(instance, object);
}
