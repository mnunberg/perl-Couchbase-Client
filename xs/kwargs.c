#include "perl-couchbase.h"

static plcb_argval_t *find_valspec(plcb_argval_t *values,
                                   const char *key,
                                   size_t nkey)
{
    plcb_argval_t *ret;
    for (ret = values; ret->key; ret++) {
        if (nkey != ret->nkey) {
            continue;
        }
        if (strncasecmp(ret->key, key, nkey) == 0) {
            return ret;
        }
    }
    return NULL;
}

static int convert_valspec(plcb_argval_t *dst, SV *src)
{
    switch (dst->type) {

    case PLCB_ARG_T_INT:
    case PLCB_ARG_T_BOOL: {

        int assigned_val = 0;

        if (SvTYPE(src) == SVt_NULL) {
            assigned_val = 0;

        } else {
            assigned_val = SvIV(src);
        }

        *((int*)(dst->value)) = assigned_val;
        break;
    }


#define EXPECT_RV(subtype, friendly_name) \
    if (SvROK(src) == 0 || SvTYPE(SvRV(src)) != subtype) { \
        die("Expected %s for %s", friendly_name, dst->key); \
    } \
    dst->value = src;

    case PLCB_ARG_T_SV:
        dst->value = src;
        break;

    case PLCB_ARG_T_HV:
        EXPECT_RV(SVt_PVHV, "Hash");
        break;

    case PLCB_ARG_T_AV:
        EXPECT_RV(SVt_PVAV, "Array");
        break;

    case PLCB_ARG_T_CV:
        EXPECT_RV(SVt_PVCV, "CODE");
        break;

#undef EXPECT_RV

    case PLCB_ARG_T_RV:
        if (!SvROK(src)) {
            die("Expected reference for %s", dst->key);
        }
        dst->value = src;
        break;

    case PLCB_ARG_T_CAS: {
        uint64_t *cas_p = NULL;
        plcb_cas_from_sv(src, cas_p);

        if (cas_p) {
            *(uint64_t*)dst->value = *cas_p;
        }

        break;

    }

    case PLCB_ARG_T_EXP:
    case PLCB_ARG_T_EXPTT: {
        IV exp_iv = SvIV(src);
        if (exp_iv < 0) {
            die("Expiry cannot be negative");
        }

        if (dst->type == PLCB_ARG_T_EXP) {
            *((UV*)dst->value) = exp_iv;
        } else {
            *(time_t*)dst->value = exp_iv;
        }

        break;
    }

    case PLCB_ARG_T_I64:
        *(int64_t*)dst->value = plcb_sv_to_64(src);
        break;

    case PLCB_ARG_T_U64:
        *(uint64_t*)dst->value = plcb_sv_to_u64(src);
        break;

    case PLCB_ARG_T_STRING:
    case PLCB_ARG_T_STRING_NN: {
        PLCB_XS_STRING_t *str = dst->value;
        str->origsv = src;
        str->base = SvPV(src, str->len);

        if (str->len == 0 && dst->type == PLCB_ARG_T_STRING_NN) {
            die("Value cannot be an empty string for %s", dst->key);
        }
        break;
    }

    default:
        return -1;
        break;

    }

    return 0;

}

/**
 * Pass a hash, as well as an array of value containers.
 */
int plcb_extract_args(HV *hash, plcb_argval_t *values)
{
    char *cur_key;
    I32 klen;
    SV *cur_val;

    hv_iterinit(hash);

    while ( (cur_val = hv_iternextsv(hash, &cur_key, &klen)) ) {

        plcb_argval_t *curdst = find_valspec(values, cur_key, klen);

        if (!curdst) {
            warn("Unrecognized key '%.*s'", (int)klen, cur_key);
            continue;
        }

        if (convert_valspec(curdst, cur_val) == -1) {
            die("Unrecognized valspec for %.*s'", (int)klen, cur_key);
        }

        curdst->sv = cur_val;
    }

    return 0;
}
