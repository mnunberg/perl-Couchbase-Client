/**
 * This is an attempt at consolidating argument handling for all functions
 * in single, multi, and async mode.
 */

#include "perl-couchbase.h"

static plcb_argval_t *
find_valspec(plcb_argval_t *values, const char *key, size_t nkey)
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

static int
convert_valspec(plcb_argval_t *dst, SV *src)
{
    switch (dst->type) {
    case PLCB_ARG_T_PAD:
        return 0;

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
    *(void**)dst->value = src;

    case PLCB_ARG_T_SV:
        *(SV**)dst->value = src;
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
        *(SV**)dst->value = src;
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
        UV exp_uv = plcb_exp_from_sv(src);

        if (dst->type == PLCB_ARG_T_EXP) {
            *((UV*)dst->value) = exp_uv;
        } else {
            *(time_t*)dst->value = exp_uv;
        }

        break;
    }

    case PLCB_ARG_T_I64:
        *(int64_t*)dst->value = plcb_sv_to_64(src);
        break;

    case PLCB_ARG_T_U64:
        *(uint64_t*)dst->value = plcb_sv_to_u64(src);
        break;

    case PLCB_ARG_T_U32:
        *(uint32_t*)dst->value = SvUV(src);
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

    case PLCB_ARG_T_CSTRING:
    case PLCB_ARG_T_CSTRING_NN: {
        *(const char **)dst->value = SvPV_nolen(src);
        if (dst->type == PLCB_ARG_T_CSTRING_NN) {
            if (dst->value == NULL|| *(const char*)dst->value == '\0') {
                die("Value passed must not be empty for %s", dst->key);
            }
        }
        break;
    }

    default:
        return -1;
        break;

    }

    return 0;

}

int
plcb_extract_args(SV *sv, plcb_argval_t *values)
{
    char *cur_key;
    I32 klen;
    if (SvROK(sv)) {
        sv = SvRV(sv);
    }

    if (SvTYPE(sv) == SVt_PVHV) {
        HV *hv = (HV*)sv;
        SV *cur_val;
        hv_iterinit(hv);

        while ( (cur_val = hv_iternextsv(hv, &cur_key, &klen)) ) {
            plcb_argval_t *curdst = find_valspec(values, cur_key, klen);

            if (!curdst) {
                warn("Unrecognized key '%.*s'", (int)klen, cur_key);
                continue;
            }

            if (convert_valspec(curdst, cur_val) == -1) {
                die("Bad value for %.*s'", (int)klen, cur_key);
            }

            curdst->sv = cur_val;
        }
    } else {
        die("Unrecognized options type. Must be hash");
    }
    return 0;
}

static void
load_doc_options(PLCB_t *parent, AV *ret, plcb_argval_t *values)
{
    plcb_argval_t *cur = values;

    for (cur = values; cur->value; cur++) {
        SV **tmpsv;
        int ix;

        if (cur->type == PLCB_ARG_T_PAD) {
            continue;
        }

        if (cur->key == PLCB_ARG_K_CAS) {
            ix = PLCB_RETIDX_CAS;
        } else if (cur->key == PLCB_ARG_K_EXPIRY) {
            ix = PLCB_RETIDX_EXP;
        } else if (cur->key == PLCB_ARG_K_VALUE) {
            ix = PLCB_RETIDX_VALUE;
        } else {
            continue;
        }
        tmpsv = av_fetch(ret, ix, 0);
        if (!tmpsv) {
            continue;
        }

        if (convert_valspec(cur, *tmpsv) == -1) {
            die("Couldn't convert %s", cur->key);
        }
        cur->sv = *tmpsv;
    }
}

int
PLCB_args_get(PLCB_t *object, plcb_SINGLEOP *args, lcb_CMDGET *gcmd)
{

    UV exp = 0;
    UV lock = 0;

    plcb_argval_t doc_specs [] = {
        PLCB_KWARG(PLCB_ARG_K_EXPIRY, EXP, &exp),
        {NULL}
    };

    plcb_argval_t opt_specs[] = {
        PLCB_KWARG(PLCB_ARG_K_LOCK, EXP, &lock),
        {NULL}
    };

    load_doc_options(object, args->docav, doc_specs);
    if (args->cmdopts) {
        plcb_extract_args(args->cmdopts, opt_specs);
    }

    if (lock) {
        PLCB_UEXP2EXP(gcmd->lock, lock, 0);
        gcmd->exptime = gcmd->lock;
    } else if (exp) {
        gcmd->exptime = exp;
    }

    return 0;
}

int
PLCB_args_remove(PLCB_t *object, plcb_SINGLEOP *args, lcb_CMDREMOVE *rcmd)
{
    uint64_t cas = 0;
    int ignore_cas = 0;
    plcb_argval_t doc_specs[] = {
        PLCB_KWARG(PLCB_ARG_K_CAS, CAS, &cas),
        { NULL }
    };
    plcb_argval_t opts_specs[] = {
        PLCB_KWARG(PLCB_ARG_K_IGNORECAS, BOOL, &ignore_cas),
        {NULL}
    };
    load_doc_options(object, args->docav, doc_specs);
    if (args->cmdopts) {
        plcb_extract_args(args->cmdopts, opts_specs);
    }
    if (ignore_cas) {
        rcmd->cas = 0;
    }
    return 0;
}

int
PLCB_args_arithmetic(PLCB_t *object, plcb_SINGLEOP *args, lcb_CMDCOUNTER *acmd)
{
    acmd->delta = 1;
    plcb_argval_t argspecs[] = {
        PLCB_KWARG(PLCB_ARG_K_ARITH_DELTA, I64, &acmd->delta),
        PLCB_KWARG(PLCB_ARG_K_ARITH_INITIAL, U64, &acmd->initial),
        PLCB_KWARG(PLCB_ARG_K_EXPIRY, EXP, &acmd->exptime),
        { NULL }
    };

    if (args->cmdopts) {
        plcb_extract_args(args->cmdopts, argspecs);
    }
    return 0;
}

int
PLCB_args_unlock(PLCB_t *object, plcb_SINGLEOP *args, lcb_CMDUNLOCK *ucmd)
{
    plcb_argval_t argspecs[] = {
        PLCB_KWARG(PLCB_ARG_K_CAS, CAS, &ucmd->cas),
        { NULL }
    };

    load_doc_options(object, args->docav, argspecs);
    if (!ucmd->cas) {
        die("Unlock command must have CAS");
    }
    return 0;
}

int
PLCB_args_set(PLCB_t *object, plcb_SINGLEOP *args, lcb_CMDSTORE *scmd, plcb_DOCVAL *vspec)
{
    UV exp = 0;
    SV *dur_sv = NULL;

    int ignore_cas = 0;
    int persist_to = 0, replicate_to = 0;

    vspec->flags = PLCB_CF_JSON;

    plcb_argval_t doc_specs[] = {
        PLCB_KWARG(PLCB_ARG_K_VALUE, SV, &vspec->value),
        PLCB_KWARG(PLCB_ARG_K_EXPIRY, EXP, &exp),
        PLCB_KWARG(PLCB_ARG_K_CAS, CAS, &scmd->cas),
        PLCB_KWARG(PLCB_ARG_K_FMT, U32, &vspec->spec),
        {NULL}
    };

    plcb_argval_t opt_specs[] = {
        PLCB_KWARG(PLCB_ARG_K_IGNORECAS, BOOL, &ignore_cas),
        PLCB_KWARG(PLCB_ARG_K_FRAGMENT, SV, &vspec->value),
        PLCB_KWARG(PLCB_ARG_K_PERSIST, INT, &persist_to),
        PLCB_KWARG(PLCB_ARG_K_REPLICATE, INT, &replicate_to),
        { NULL }
    };

    if (args->cmdbase == PLCB_CMD_APPEND || args->cmdbase == PLCB_CMD_PREPEND) {
        doc_specs[0].type = PLCB_ARG_T_PAD;
    } else {
        opt_specs[1].type = PLCB_ARG_T_PAD;
    }

    load_doc_options(object, args->docav, doc_specs);
    if (args->cmdopts) {
        plcb_extract_args(args->cmdopts, opt_specs);
    }

    scmd->exptime = exp;
    if (ignore_cas) {
        scmd->cas = 0;
    }

    dur_sv = *av_fetch(args->docav, PLCB_RETIDX_OPTIONS, 1);
    if (SvIOK(dur_sv)) {
        SvUVX(dur_sv) = PLCB_MKDURABILITY(persist_to, replicate_to);
    } else {
        sv_setuv(dur_sv, PLCB_MKDURABILITY(persist_to, replicate_to));
    }

    if (!vspec->value) {
        die("Must have value!");
    }
    return 0;
}
