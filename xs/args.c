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

int
extract_args(SV *sv, plcb_argval_t *values)
{
    char *cur_key;
    I32 klen;
    SV *cur_val;

    if (SvROK(cur_val)) {
        cur_val = SvRV(cur_val);
    }

    if (SvTYPE(sv) == SVt_PVAV) {
        AV *av = (AV*)sv;
        plcb_argval_t *cur = values;
        I32 ii;
        I32 maxlen = av_len(av) + 1;
        for (cur = values; cur->key && ii < maxlen; cur++, ii++) {
            SV *elem = *(av_fetch(av, ii, 0));
            if (convert_valspec(cur, elem) == -1) {
                die("Malformed element at index %d (%s)", ii, cur->key);
            }
            cur->sv = elem;
        }

    } else if (SvTYPE(sv) == SVt_PVHV) {
        HV *hv = (HV*)sv;
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
        die("Unrecognized options type. Must be hash or array");
    }
    return 0;
}

int
PLCB_args_get(PLCB_t *object, SV *opts, lcb_CMDGET *gcmd, PLCB_schedctx_t *ctx)
{

    UV exp = 0;
    UV lock = 0;

    plcb_argval_t argspecs[] = {
        PLCB_KWARG(PLCB_ARG_K_EXPIRY, EXP, &exp),
        PLCB_KWARG(PLCB_ARG_K_LOCK, EXP, &lock),
        { NULL }
    };

    extract_args(opts, argspecs);
    if (exp) {
        PLCB_UEXP2EXP(gcmd->exptime, exp, 0);
    }

    if (lock) {
        PLCB_UEXP2EXP(gcmd->lock, lock, 0);
        gcmd->exptime = gcmd->lock;
    }

    return 0;
}

int
PLCB_args_lock(PLCB_t *object, SV *options, lcb_CMDGET *gcmd, PLCB_schedctx_t *ctx)
{
    PLCB_args_get(object, options, gcmd, ctx);
    gcmd->lock = 1;
    return 0;
}

int
PLCB_args_touch(PLCB_t *object, SV *options, lcb_CMDTOUCH *tcmd,
    PLCB_schedctx_t *ctx)
{
    UV exp = 0;
    plcb_argval_t argspecs[] = {
        PLCB_KWARG(PLCB_ARG_K_EXPIRY, EXP, &exp),
        { NULL }
    };

    extract_args(options, argspecs);

    if (exp) {
        PLCB_UEXP2EXP(tcmd->exptime, exp, 0);
    }

    return 0;
}

int
PLCB_args_remove(PLCB_t *object, SV *options, lcb_CMDREMOVE *rcmd, PLCB_schedctx_t *ctx)
{
    uint64_t cas = 0;
    plcb_argval_t argspec[] = {
        PLCB_KWARG(PLCB_ARG_K_CAS, CAS, &cas),
        { NULL }
    };

    extract_args(options, argspec);
    rcmd->cas = cas;
    return 0;
}

int
PLCB_args_arithmetic(PLCB_t *object, SV *options, lcb_CMDCOUNTER *acmd,
    PLCB_schedctx_t *ctx)
{
    UV exp = 0;
    UV delta;
    plcb_argval_t argspecs[] = {
        PLCB_KWARG(PLCB_ARG_K_ARITH_DELTA, I64, &acmd->delta),
        PLCB_KWARG(PLCB_ARG_K_ARITH_INITIAL, U64, &acmd->initial),
        PLCB_KWARG(PLCB_ARG_K_EXPIRY, EXP, &acmd->exptime),
        { NULL }
    };

    extract_args(options, argspecs);

    return 0;
}

int
PLCB_args_incr(PLCB_t *object, SV *options, lcb_CMDCOUNTER *acmd, PLCB_schedctx_t *ctx)
{
    return PLCB_args_arithmetic(object, options, acmd, ctx);
}

int
PLCB_args_decr(PLCB_t *object, SV *options, lcb_CMDCOUNTER *acmd, PLCB_schedctx_t *ctx)
{
    int ret = PLCB_args_incr(object, options, acmd, ctx);
    if (ret != -1) {
        acmd->delta *= -1;
    }
    return ret;
}

int
PLCB_args_unlock(PLCB_t *object, SV *options, lcb_CMDUNLOCK *ucmd, PLCB_schedctx_t *ctx)
{
    plcb_argval_t argspecs[] = {
        PLCB_KWARG(PLCB_ARG_K_CAS, CAS, &ucmd->cas),
        { NULL }
    };

    extract_args(options, argspecs);
    if (!ucmd->cas) {
        die("Unlock command must have CAS");
    }
    return 0;
}

int
PLCB_args_set(PLCB_t *object,
    SV *options, lcb_CMDSTORE *scmd, PLCB_schedctx_t *ctx, SV **valuesv,
    int cmdcode)
{
    UV exp = 0;
    plcb_argval_t kwspec[] = {
        PLCB_KWARG(PLCB_ARG_K_VALUE, SV, valuesv),
        PLCB_KWARG(PLCB_ARG_K_EXPIRY, EXP, &exp),
        PLCB_KWARG(PLCB_ARG_K_CAS, CAS, &scmd->cas),
        {NULL}
    };

    if (valuesv == NULL) {
        /* Set the defaults */
        kwspec[0].type = PLCB_ARG_T_PAD;
        if (cmdcode & PLCB_COMMANDf_MULTI) {
            kwspec[2].type = PLCB_ARG_T_PAD;
        }
    }

    extract_args(options, kwspec);
    scmd->exptime = exp;
    return 0;
}
