/**
 * This is an attempt at consolidating argument handling for all functions
 * in single, multi, and async mode.
 */

#include "perl-couchbase.h"

#define is_opthash(sv) \
    (SvROK(sv) && SvTYPE(SvRV(sv)) == SVt_PVHV)


#define _ARG_ERROR(e) \
    ao->errmsg = e; \
    if (ao->autodie) { \
        die(e); \
    } \
    return -1;

#define _ARG_NOW (ao->now)

int PLCB_args_get(PLCB_t *object,
                  SV **args,
                  int nargs,
                  lcb_get_cmd_t *gcmd,
                  PLCB_argopts_t *ao)
{

    UV exp = 0;
    UV lock = 0;

    plcb_argval_t argspecs[] = {
        PLCB_KWARG(PLCB_ARG_K_EXPIRY, EXP, &exp),
        PLCB_KWARG(PLCB_ARG_K_LOCK, EXP, &lock),
        { NULL }
    };

    if (nargs == 0 || nargs > 2) {
        _ARG_ERROR("get(key, { options });");
    }

    plcb_get_str_or_die(args[0], gcmd->v.v0.key, gcmd->v.v0.nkey, "key");

    if (nargs == 2) {
        if (is_opthash(args[1])) {
            plcb_extract_args((HV*)SvRV(args[1]), argspecs);
        } else {
            exp = plcb_exp_from_sv(args[1]);
            exp = PLCB_UEXP2EXP(gcmd->v.v0.exptime, exp, _ARG_NOW);
        }
    }


    if (lock) {
        lock = PLCB_UEXP2EXP(gcmd->v.v0.lock, lock, 0);
        gcmd->v.v0.lock = 1;
    }

    return 0;
}

int PLCB_args_lock(PLCB_t *object,
                   SV **args,
                   int nargs,
                   lcb_get_cmd_t *gcmd,
                   PLCB_argopts_t *ao)
{
    UV exp;
    if (nargs != 2) {
        _ARG_ERROR("lock(key, exptime)");
    }

    plcb_get_str_or_die(args[0], gcmd->v.v0.key, gcmd->v.v0.nkey, "key");
    exp = plcb_exp_from_sv(args[1]);
    if (!exp) {
        _ARG_ERROR("Lock timeout must be positive");
    }

    PLCB_UEXP2EXP(gcmd->v.v0.exptime, exp, _ARG_NOW);
    gcmd->v.v0.lock = 1;

    return 0;
}

int PLCB_args_touch(PLCB_t *object,
                    SV **args,
                    int nargs,
                    lcb_touch_cmd_t *tcmd,
                    PLCB_argopts_t *ao)
{
    if (nargs != 2) {
        _ARG_ERROR("touch(key, exp)");
    }

    plcb_get_str_or_die(args[0], tcmd->v.v0.key, tcmd->v.v0.nkey, "key");
    tcmd->v.v0.exptime = plcb_exp_from_sv(args[1]);
    return 0;
}

int PLCB_args_remove(PLCB_t *object,
                     SV **args,
                     int nargs,
                     lcb_remove_cmd_t *rcmd,
                     PLCB_argopts_t *ao)
{
    uint64_t cas = 0, *cas_p = NULL;

    plcb_argval_t argspec[] = {
        PLCB_KWARG(PLCB_ARG_K_CAS, CAS, &cas),
        { NULL }
    };

    if (nargs < 1 || nargs > 2) {
        _ARG_ERROR("remove(key, [cas]); remove(key, { options })");
    }

    plcb_get_str_or_die(args[0], rcmd->v.v0.key, rcmd->v.v0.nkey, "key");

    if (nargs == 2) {
        if (is_opthash(args[1])) {
            plcb_extract_args((HV*)SvRV(args[1]), argspec);
        } else {
            plcb_cas_from_sv(args[1], cas_p);
            if (cas_p) {
                cas = *cas_p;
            }
        }
        rcmd->v.v0.cas = cas;
    }

    return 0;
}

int PLCB_args_arithmetic(PLCB_t *object,
                         SV **args,
                         int nargs,
                         lcb_arithmetic_cmd_t *acmd,
                         PLCB_argopts_t *ao)
{
    UV exp = 0;
    plcb_argval_t argspecs[] = {
            PLCB_KWARG(PLCB_ARG_K_EXPIRY, EXP, &exp),
            { NULL }
    };

    if (nargs > 4 || nargs < 3) {
        _ARG_ERROR("arithmetic(key, delta, initial, [ ,expiry/{options} ]");
    }

    plcb_get_str_or_die(args[0], acmd->v.v0.key, acmd->v.v0.nkey, "key");

    acmd->v.v0.delta = plcb_sv_to_64(args[1]);

    if (SvTYPE(args[2]) != SVt_NULL) {
        acmd->v.v0.create = 1;
        acmd->v.v0.initial = plcb_sv_to_u64(args[2]);
    }

    if (nargs == 4) {
        if (is_opthash(args[3])) {
            plcb_extract_args((HV*)SvRV(args[3]), argspecs);
            acmd->v.v0.exptime = exp;

        } else {
            PLCB_UEXP2EXP(acmd->v.v0.exptime,
                          plcb_exp_from_sv(args[3]),
                          _ARG_NOW);
        }
    }

    return 0;
}

int PLCB_args_incrdecr(PLCB_t *object,
                       SV **args,
                       int nargs,
                       lcb_arithmetic_cmd_t *acmd,
                       PLCB_argopts_t *ao)
{
    int64_t delta = 0;
    uint64_t initial = 0;
    UV exp = 0;

    plcb_argval_t argspecs[] = {
        PLCB_KWARG(PLCB_ARG_K_ARITH_DELTA, I64, &delta),
        PLCB_KWARG(PLCB_ARG_K_ARITH_INITIAL, U64, &initial),
        PLCB_KWARG(PLCB_ARG_K_EXPIRY, EXP, &exp),
        { NULL }
    };

    if (nargs < 1 || nargs > 2) {
        _ARG_ERROR("incr/decr(key, [, delta/options])");
    }

    plcb_get_str_or_die(args[0], acmd->v.v0.key, acmd->v.v0.nkey, "key");

    if (nargs == 2) {
        if (is_opthash(args[1])) {
            plcb_extract_args((HV*)SvRV(args[1]), argspecs);

            if (!argspecs[0].sv) {
                delta = 1;
            }

            acmd->v.v0.delta = delta;
            PLCB_UEXP2EXP(acmd->v.v0.exptime, exp, _ARG_NOW);

            if (argspecs[1].sv) {
                acmd->v.v0.create = 1;
                acmd->v.v0.initial = initial;
            }

        } else {
            acmd->v.v0.delta = plcb_sv_to_64(args[1]);
        }

    } else {
        acmd->v.v0.delta = 1;
    }
    return 0;
}

int PLCB_args_unlock(PLCB_t *object,
                     SV **args,
                     int nargs,
                     lcb_unlock_cmd_t *ucmd,
                     PLCB_argopts_t *ao)
{
    uint64_t *cas_p = NULL;
    if (nargs != 2) {
        _ARG_ERROR("unlock(key, cas)");
    }

    plcb_get_str_or_die(args[0], ucmd->v.v0.key, ucmd->v.v0.nkey, "key");
    plcb_cas_from_sv(args[1], cas_p);
    ucmd->v.v0.cas = *cas_p;
    return 0;
}

int PLCB_args_set(PLCB_t *object,
                  SV **args,
                  int nargs,
                  lcb_store_cmd_t *scmd,
                  PLCB_argopts_t *ao)
{
    UV exp = 0;
    uint64_t cas = 0;

    plcb_argval_t kwspec[] = {
        PLCB_KWARG(PLCB_ARG_K_EXPIRY, EXP, &exp),
        PLCB_KWARG(PLCB_ARG_K_CAS, CAS, &cas),
        { NULL }
    };

    if (nargs < 2 || nargs > 3) {
        _ARG_ERROR("mutate(key, value, [ exp/{options} ])");
    }

    plcb_get_str_or_die(args[0], scmd->v.v0.key, scmd->v.v0.nkey, "key");

    /**
     * We ignore the value for now..
     */
    if (nargs == 3) {
        if (is_opthash(args[2])) {
            plcb_extract_args((HV*)SvRV(args[2]), kwspec);
            scmd->v.v0.cas = cas;
        } else {
            exp = plcb_exp_from_sv(args[2]);
        }
    }

    if (exp) {
        PLCB_UEXP2EXP(scmd->v.v0.exptime, exp, _ARG_NOW);
    }

    return 0;
}

int PLCB_args_cas(PLCB_t *object,
                  SV **args,
                  int nargs,
                  lcb_store_cmd_t *scmd,
                  PLCB_argopts_t *ao)
{
    UV exp = 0;
    uint64_t *cas_p;

    plcb_argval_t kwspec[] = {
        PLCB_KWARG(PLCB_ARG_K_EXPIRY, EXP, &exp),
        { NULL }
    };

    if (nargs < 3 || nargs > 4) {
        _ARG_ERROR("cas(key, value, cas [, exp/{options} ])");
    }

    plcb_cas_from_sv(args[2], cas_p);
    scmd->v.v0.cas = *cas_p;

    plcb_get_str_or_die(args[0], scmd->v.v0.key, scmd->v.v0.nkey, "key");
    if (nargs == 4) {
        if (is_opthash(args[3])) {
            plcb_extract_args((HV*)SvRV(args[3]), kwspec);
        } else {
            exp = plcb_exp_from_sv(args[3]);
        }
    }

    if (exp) {
        PLCB_UEXP2EXP(scmd->v.v0.exptime, exp, _ARG_NOW);
    }

    return 0;
}
