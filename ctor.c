#include "perl-couchbase.h"

void plcb_ctor_cbc_opts(
    AV *options, char **hostp, char **userp, char **passp, char **bucketp)
{
    
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

void plcb_ctor_conversion_opts(PLCB_t *object, AV *options)
{
    SV **tmpsv;
    AV *methav;
    int dummy;
    
#define meth_assert_getpairs(flag, optidx) \
    ((object->my_flags & flag) \
    ? \
        (((tmpsv = av_fetch(options, optidx, 0)) && SvROK(*tmpsv) && \
            (methav = (AV*)SvRV(*tmpsv))) \
            ? (void*)1 \
            :  die("Flag %s specified but no methods provided", #flag)) \
    : NULL)
    
#define meth_assert_assign(target_field, source_idx, diemsg) \
    if((tmpsv = av_fetch(methav, source_idx, 0)) == NULL) { \
        die("Nothing in IDX=%d (%s)", source_idx, diemsg); \
    } \
    if(! ((SvROK(*tmpsv) && SvTYPE(SvRV(*tmpsv)) == SVt_PVCV) ) ) { \
        die("Expected CODE reference at IDX=%d: %s",source_idx, diemsg); \
    } \
    object->target_field = newRV_inc(SvRV(*tmpsv));

    
    if( (tmpsv = av_fetch(options, PLCB_CTORIDX_MYFLAGS, 0))
       && SvIOK(*tmpsv)) {
        object->my_flags = SvUV(*tmpsv);
    }
    
    if(meth_assert_getpairs(PLCBf_USE_COMPRESSION,
                                  PLCB_CTORIDX_COMP_METHODS)) {
        meth_assert_assign(cv_compress, 0, "Compression");
        meth_assert_assign(cv_decompress, 1, "Decompression");
    }
    
    if(meth_assert_getpairs(PLCBf_USE_STORABLE,
                                  PLCB_CTORIDX_SERIALIZE_METHODS)) {
        meth_assert_assign(cv_serialize, 0, "Serialize");
        meth_assert_assign(cv_deserialize, 1, "Deserialize");

    }
    
    if( (tmpsv = av_fetch(options, PLCB_CTORIDX_COMP_THRESHOLD, 0))
       && SvIOK(*tmpsv)) {
        object->compress_threshold = SvIV(*tmpsv);
    } else {
        object->compress_threshold = 0;
    }
}

void plcb_ctor_init_common(PLCB_t *object, libcouchbase_t instance,
                           AV *options)
{
    NV timeout_value;
    SV **tmpsv;
    
    object->instance = instance;
    object->errors = newAV();
    if(! (object->ret_stash = gv_stashpv(PLCB_RET_CLASSNAME, 0)) ) {
        die("Could not load '%s'", PLCB_RET_CLASSNAME);
    }
    
    /*gather instance-related options from the constructor*/
    if( (tmpsv = av_fetch(options, PLCB_CTORIDX_TIMEOUT, 0)) ) {
        timeout_value = SvNV(*tmpsv);
        if(!timeout_value) {
            warn("Cannot use 0 for timeout");
        } else {
            libcouchbase_set_timeout(instance,
                timeout_value * (1000*1000));
        }
    }
    
    if((tmpsv = av_fetch(options, PLCB_CTORIDX_NO_CONNECT, 0)) &&
       SvTRUE(*tmpsv)) {
        object->my_flags |= PLCBf_NO_CONNECT;
    }
    /*maybe more stuff here?*/
}
