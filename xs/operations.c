#include "perl-couchbase.h"
#include <libcouchbase/api3.h>

#ifndef mk_instance_vars
#define mk_instance_vars(sv, inst_name, obj_name) \
    if (!SvROK(sv)) { \
        die("self must be a reference"); \
    } \
    obj_name = NUM2PTR(PLCB_t*, SvIV(SvRV(sv))); \
    if(!obj_name) { \
        die("tried to access de-initialized PLCB_t"); \
    } \
    inst_name = obj_name->instance;

#endif

static void
get_argiter_cb(PLCB_schedctx_t *ctx, const char *key, lcb_SIZE nkey, SV *options)
{
    lcb_CMDGET get = ctx->args->u_template.get;
    LCB_CMD_SET_KEY(&get, key, nkey);

    if (options == NULL) {
        if (ctx->cmdbase != PLCB_CMD_GET) {
            die("Bare-keys only work with get()");
        }

    } else {
        if (ctx->cmdbase == PLCB_CMD_GET) {
            PLCB_args_get(ctx->parent, options, &get, ctx);
        } else if (ctx->cmdbase == PLCB_CMD_LOCK) {
            PLCB_args_lock(ctx->parent, options, &get, ctx);
        } else {
            die("Got unknown cmd_base=%d", ctx->cmdbase);
        }
    }
    ctx->err = lcb_get3(ctx->parent->instance, ctx->cookie, &get);
    if (ctx->err != LCB_SUCCESS) {
        ctx->loop = 0;
    }
}

SV *
PLCB_op_get(SV *self, PLCB_args_t *args)
{
    PLCB_t *object;
    lcb_t instance;
    PLCB_schedctx_t ctx = { NULL };
    mk_instance_vars(self, instance, object);

    ctx.flags = PLCB_ARGITERf_RAWKEY_OK|PLCB_ARGITERf_RAWVAL_OK|PLCB_ARGITERf_SINGLE_OK;
    plcb_schedctx_init_common(object, self, args, NULL, &ctx);

    if (args->cmdopts) {
        PLCB_args_get(object, (SV*)args->cmdopts, &args->u_template.get, &ctx);
    }

    plcb_schedctx_iter_start(&ctx);
    plcb_schedctx_iter_run(&ctx, get_argiter_cb);

    if (ctx.err != LCB_SUCCESS) {
        lcb_sched_fail(instance);
        plcb_schedctx_iter_bail(&ctx, ctx.err);
    }
    return plcb_schedctx_return(&ctx);
}

typedef struct {
    plcb_conversion_spec_t spec;
    lcb_storage_t storop;
} my_STOREINFO;

static void
store_argiter_cb(PLCB_schedctx_t *ctx, const char *key, lcb_SIZE nkey, SV *options)
{
    STRLEN nvalue = 0;
    char *value = NULL;
    SV *value_sv = NULL;

    uint32_t store_flags = 0;
    lcb_CMDSTORE scmd = ctx->args->u_template.store;
    my_STOREINFO *info = ctx->priv;

    LCB_CMD_SET_KEY(&scmd, key, nkey);
    if (options == NULL) {
        value_sv = ctx->args->value;
    } else if (!SvROK(options)) {
        value_sv = options;
    } else {
        PLCB_args_set(ctx->parent, options, &scmd, ctx, &value_sv, ctx->args->cmd);
    }
    plcb_convert_storage(ctx->parent, &value_sv, &nvalue, &store_flags, info->spec);
    if (value_sv == NULL) {
        die("Invalid value!");
    }
    if (nvalue == 0) {
        if (SvTYPE(value_sv) == SVt_PV) {
            nvalue = SvCUR(value_sv);
            value = SvPVX(value_sv);
        } else {
            value = SvPV(value_sv, nvalue);
        }
    }
    LCB_CMD_SET_VALUE(&scmd, value, nvalue);

    scmd.flags = store_flags;
    scmd.operation = info->storop;
    ctx->err = lcb_store3(ctx->parent->instance, ctx->cookie, &scmd);
    plcb_convert_storage_free(ctx->parent, value_sv, store_flags);
    if (ctx->err != LCB_SUCCESS) {
        ctx->loop = 0;
    }
}

SV*
PLCB_op_set(SV *self, PLCB_args_t *args)
{
    PLCB_schedctx_t ctx = { NULL };
    my_STOREINFO info = { 0 };
    PLCB_t *object;
    lcb_t instance;
    
    mk_instance_vars(self, instance, object);
    plcb_schedctx_init_common(object, self, args, NULL, &ctx);
    ctx.priv = &info;
    info.storop = plcb_command_to_storop(ctx.cmdbase);
    info.spec = PLCB_CONVERT_SPEC_NONE;

    if (args->cmdopts) {
        PLCB_args_set(object, (SV*)args->cmdopts, &args->u_template.store,
            &ctx, NULL, args->cmd);
    }

    plcb_schedctx_iter_start(&ctx);
    plcb_schedctx_iter_run(&ctx, store_argiter_cb);

    if (ctx.err != LCB_SUCCESS) {
        lcb_sched_fail(object->instance);
        plcb_schedctx_iter_bail(&ctx, ctx.err);
    }
    return plcb_schedctx_return(&ctx);
}

static void
arith_argiter_cb(PLCB_schedctx_t *ctx, const char *key, lcb_SIZE nkey, SV *options)
{
    lcb_CMDCOUNTER acmd = { 0 };

    LCB_CMD_SET_KEY(&acmd, key, nkey);

    if (options) {
        if (!SvROK(options)) {
            acmd.delta = plcb_sv_to_64(options);
            options = NULL;
        } else {
            if (ctx->cmdbase == PLCB_CMD_ARITHMETIC) {
                PLCB_args_arithmetic(ctx->parent, options, &acmd, ctx);
            } else if (ctx->cmdbase == PLCB_CMD_INCR) {
                PLCB_args_incr(ctx->parent, options, &acmd, ctx);
            } else {
                PLCB_args_decr(ctx->parent, options, &acmd, ctx);
            }
        }
    } else {
        acmd.delta = 1;
    }
    if (options == NULL && ctx->cmdbase == PLCB_CMD_DECR) {
        acmd.delta *= -1;
    }

    ctx->err = lcb_counter3(ctx->parent->instance, ctx->cookie, &acmd);
    if (ctx->err != LCB_SUCCESS) {
        ctx->loop = 0;
    }
}

SV*
PLCB_op_counter(SV *self, PLCB_args_t *args)
{
    PLCB_schedctx_t ctx = { NULL };
    lcb_t instance;
    PLCB_t *obj;
    
    ctx.flags = PLCB_ARGITERf_RAWKEY_OK|PLCB_ARGITERf_RAWVAL_OK|PLCB_ARGITERf_SINGLE_OK;

    mk_instance_vars(self, instance, obj);
    plcb_schedctx_init_common(obj, self, args, NULL, &ctx);
    plcb_schedctx_iter_start(&ctx);
    plcb_schedctx_iter_run(&ctx, arith_argiter_cb);

    if (ctx.err != LCB_SUCCESS) {
        lcb_sched_fail(instance);
        plcb_schedctx_iter_bail(&ctx, ctx.err);
    }
    return plcb_schedctx_return(&ctx);
}

static void
remove_argiter_cb(PLCB_schedctx_t *ctx, const char *key, lcb_SIZE nkey, SV *opts)
{
    lcb_CMDREMOVE rmcmd = { 0 };
    if (opts) {
        PLCB_args_remove(ctx->parent, opts, &rmcmd, ctx);
    }
    LCB_CMD_SET_KEY(&rmcmd, key, nkey);
    ctx->err = lcb_remove3(ctx->parent->instance, ctx->cookie, &rmcmd);
    if (ctx->err != LCB_SUCCESS) {
        ctx->loop = 0;
    }
}

SV*
PLCB_op_remove(SV *self, PLCB_args_t *args)
{
    lcb_t instance;
    PLCB_t *obj;
    PLCB_schedctx_t ctx = { NULL };

    ctx.flags = PLCB_ARGITERf_RAWKEY_OK|PLCB_ARGITERf_RAWVAL_OK|PLCB_ARGITERf_SINGLE_OK;

    mk_instance_vars(self, instance, obj);
    plcb_schedctx_init_common(obj, self, args, NULL, &ctx);
    plcb_schedctx_iter_start(&ctx);
    plcb_schedctx_iter_run(&ctx, remove_argiter_cb);

    if (ctx.err != LCB_SUCCESS) {
        lcb_sched_fail(instance);
        plcb_schedctx_iter_bail(&ctx, ctx.err);
    }

    return plcb_schedctx_return(&ctx);
}

static void
unlock_argiter_cb(PLCB_schedctx_t *ctx, const char *key, lcb_SIZE nkey, SV *opts)
{
    lcb_CMDUNLOCK ucmd = { 0 };
    if (!opts) {
        die("Unlock must be given a CAS");
    }
    PLCB_args_unlock(ctx->parent, opts, &ucmd, ctx);
    LCB_CMD_SET_KEY(&ucmd, key, nkey);
    ctx->err = lcb_unlock3(ctx->parent->instance, ctx->cookie, &ucmd);
    if (ctx->err != LCB_SUCCESS) {
        ctx->loop = 0;
    }
}

SV*
PLCB_op_unlock(SV *self, PLCB_args_t *args)
{
    lcb_t instance;
    PLCB_t *obj;
    PLCB_schedctx_t ctx = { NULL };

    mk_instance_vars(self, instance, obj);
    plcb_schedctx_init_common(obj, self, args, NULL, &ctx);
    plcb_schedctx_iter_start(&ctx);
    plcb_schedctx_iter_run(&ctx, unlock_argiter_cb);

    if (ctx.err != LCB_SUCCESS) {
        lcb_sched_fail(instance);
        plcb_schedctx_iter_bail(&ctx, ctx.err);
    }

    return plcb_schedctx_return(&ctx);
}
