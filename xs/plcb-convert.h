#ifndef PLCB_CONVERT_H_
#define PLCB_CONVERT_H_

#ifndef PERL_COUCHBASE_H_
#error "Include perl-couchbase.h, not this file directly"
#endif /* PERL_COUCHBASE_H_ */

 #define PLCB_STOREf_COMPAT_STORABLE 0x01LU
#define PLCB_STOREf_COMPAT_COMPRESS 0x02LU
#define PLCB_STOREf_COMPAT_UTF8     0x04LU

#define plcb_storeflags_has_compression(obj, flags) \
    (flags & PLCB_STOREf_COMPAT_COMPRESS)
#define plcb_storeflags_has_serialization(obj, flags) \
    (flags & PLCB_STOREf_COMPAT_STORABLE)
#define plcb_storeflags_has_utf8(obj, flags) \
    (flags & PLCB_STOREf_COMPAT_UTF8)

#define plcb_storeflags_has_conversion(obj, flags) \
    (plcb_storeflags_has_serialization(obj,flags) || \
     plcb_storeflags_has_compression(obj,flags)) \
     

#define plcb_should_do_compression(obj, flags) \
    ((obj->my_flags & PLCBf_USE_COMPRESSION) \
    && plcb_storeflags_has_compression(obj, flags))

#define plcb_should_do_serialization(obj, flags) \
    ((obj->my_flags & PLCBf_USE_STORABLE) \
    && plcb_storeflags_has_serialization(obj, flags))

#define plcb_should_do_utf8(obj, flags) \
    ((obj->my_flags & PLCBf_USE_CONVERT_UTF8) \
    && plcb_storeflags_has_utf8(obj, flags))

#define plcb_should_do_conversion(obj, flags) \
    (plcb_should_do_compression(obj,flags) \
    || plcb_should_do_serialization(obj, flags) \
    || plcb_should_do_utf8(obj, flags))

#define plcb_storeflags_apply_compression(obj, flags) \
    flags |= PLCB_STOREf_COMPAT_COMPRESS
#define plcb_storeflags_apply_serialization(obj, flags) \
    flags |= PLCB_STOREf_COMPAT_STORABLE
#define plcb_storeflags_apply_utf8(obj, flags) \
    flags |= PLCB_STOREf_COMPAT_UTF8

#endif /* PLCB_CONVERT_H_ */