#include "perl-couchbase.h"

#define CONVERT_DIRECTION_OUT 1
#define CONVERT_DIRECTION_IN 2

static SV*
serialize_convert(SV *meth, SV *input, int direction)
{
    dSP;
    SV *ret;
    int count;    

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    XPUSHs(input);
    PUTBACK;

    if (direction == CONVERT_DIRECTION_OUT) {
        count = call_sv(meth, G_SCALAR);
        SPAGAIN;

        /*for ouptut we must have this function succeed!*/
        if (count != 1) {
            croak("Serialization method returned nothing!");
        }
        ret = POPs;

    } else {
        count = call_sv(meth, G_SCALAR|G_EVAL);
        SPAGAIN;

        /*if someone has messed up our flags, don't die, but throw a warning*/
        if (SvTRUE(ERRSV)) {
            warn("Couldn't deserialize data: %s", SvPV_nolen(ERRSV));
            ret = input;

        } else {
            if (count != 1) {
                croak("Serialization method returned nothing?");
            }
            ret = POPs;
        }
    }

    SvREFCNT_inc(ret);
    FREETMPS;
    LEAVE;
    return ret;
}

static SV *
custom_convert(AV *docav, SV *meth, SV *input, uint32_t *flags, int direction)
{
    dSP;
    SV *ret;
    SV *flags_rv;
    SV *input_rv;
    int callflags;

    ENTER; SAVETMPS;
    PUSHMARK(SP);

    input_rv = sv_2mortal(newRV_inc(input));
    flags_rv = sv_2mortal(newRV_noinc(newSVuv(*flags)));

    XPUSHs(sv_2mortal(newRV_inc( (SV *)docav)));
    XPUSHs(input_rv);
    XPUSHs(flags_rv);

    PUTBACK;

    callflags = G_VOID|G_DISCARD;
    if (direction == CONVERT_DIRECTION_OUT) {
        callflags |= G_EVAL;
    }

    call_sv(meth, callflags);
    SPAGAIN;

    if (SvTRUE(ERRSV)) {
        ret = input;
    } else {
        warn("Conversion function failed");
        ret = SvRV(input_rv);
        *flags = SvUV(SvRV(flags_rv));
    }

    SvREFCNT_inc(ret);
    return ret;
}

void
plcb_convert_storage(PLCB_t *object, AV *docav, plcb_vspec_t *vspec)
{
    SV *pv = SvROK(vspec->value) ? SvRV(vspec->value) : vspec->value;
    uint32_t fmt = vspec->spec;
    uint32_t compat_flags = 0;

    if (object->cv_customenc) {
        vspec->need_free = 1;
        vspec->value = custom_convert(docav, object->cv_customenc,
            vspec->value, &vspec->flags, CONVERT_DIRECTION_OUT);

    } else if (fmt == PLCB_CF_JSON) {
        compat_flags = PLCB_LF_JSON;
        vspec->need_free = 1;
        vspec->value = serialize_convert(
            object->cv_jsonenc, vspec->value, CONVERT_DIRECTION_OUT);

    } else if (fmt == PLCB_CF_STORABLE) {
        compat_flags = PLCB_CF_STORABLE;
        vspec->need_free = 1;
        vspec->value = serialize_convert(
            object->cv_serialize, vspec->value, CONVERT_DIRECTION_OUT);

    } else if (fmt == PLCB_CF_RAW) {
        compat_flags = PLCB_CF_RAW;
        if (SvTYPE(pv) != SVt_PV) {
            die("Raw conversion requires string value!");
        }
    } else if (vspec->spec == PLCB_CF_UTF8) {
        compat_flags = PLCB_CF_UTF8;
        sv_utf8_upgrade(pv);
    }

    /* Assume the resultant value is an SV */
    if (SvTYPE(vspec->value) == SVt_PV) {
        vspec->encoded = SvPVX(vspec->value);
        vspec->len = SvCUR(vspec->value);
    } else {
        vspec->encoded = SvPV(vspec->value, vspec->len);
    }
    vspec->flags |= compat_flags;
}

void plcb_convert_storage_free(PLCB_t *object, plcb_vspec_t *vs)
{
    if (vs->need_free) {
        SvREFCNT_dec(vs->value);
    }
}

SV*
plcb_convert_retrieval(PLCB_t *object, AV *docav,
    const char *data, size_t data_len, uint32_t flags)
{
    SV *ret_sv, *input_sv;
    uint32_t f_common, f_legacy;
    input_sv = newSVpvn(data, data_len);

    f_common = flags & PLCB_CF_MASK;
    f_legacy = flags & PLCB_LF_MASK;

#define IS_FMT(fbase) \
    f_common == PLCB_CF_##fbase || f_legacy == PLCB_LF_##fbase

    if (object->cv_customdec) {
        ret_sv = custom_convert(docav, object->cv_customdec, input_sv, &flags,
            CONVERT_DIRECTION_IN);

    } else if (IS_FMT(JSON)) {
        ret_sv = serialize_convert(object->cv_jsondec, input_sv,
            CONVERT_DIRECTION_IN);

    } else if (IS_FMT(STORABLE)) {
        ret_sv = serialize_convert(object->cv_deserialize, input_sv,
            CONVERT_DIRECTION_IN);

    } else if (IS_FMT(RAW)) {
        ret_sv = input_sv;
        SvREFCNT_inc(ret_sv);

    } else if (IS_FMT(UTF8)) {
        SvUTF8_on(input_sv);
        ret_sv = input_sv;
        SvREFCNT_inc(ret_sv);

    } else {
        warn("Unrecognized flags 0x%x. Assuming raw", flags);
        ret_sv = input_sv;
    }

#undef IS_FMT

    SvREFCNT_dec(input_sv);
    return ret_sv;
}
