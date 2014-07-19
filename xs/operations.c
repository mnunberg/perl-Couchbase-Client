#include "perl-couchbase.h"
#include <libcouchbase/api3.h>

static void
get_argiter_cb(PLCB_schedctx_t *ctx, const char *key, lcb_SIZE nkey,
    SV *doc, SV *options)
{
    lcb_CMDGET get = ctx->args->u_template.get;
    LCB_CMD_SET_KEY(&get, key, nkey);
    if (ctx->cmdbase == PLCB_CMD_GET) {
        PLCB_args_get(ctx->parent, doc, options, &get, ctx);
    } else {
        PLCB_args_lock(ctx->parent, doc, options, &get, ctx);
    }
    ctx->err = lcb_get3(ctx->parent->instance, ctx->cookie, &get);
    if (ctx->err != LCB_SUCCESS) {
        ctx->loop = 0;
    }
}

SV *
PLCB_op_get(PLCB_t *object, PLCB_args_t *args)
{
    PLCB_schedctx_t ctx = { NULL };

    ctx.flags = PLCB_ARGITERf_RAWKEY_OK|PLCB_ARGITERf_RAWVAL_OK|PLCB_ARGITERf_SINGLE_OK;
    plcb_schedctx_init_common(object, args, NULL, &ctx);

    if (args->cmdopts) {
        PLCB_args_get(object, NULL, (SV*)args->cmdopts, &args->u_template.get, &ctx);
    }

    plcb_schedctx_iter_start(&ctx);
    plcb_schedctx_iter_run(&ctx, get_argiter_cb);

    if (ctx.err != LCB_SUCCESS) {
        lcb_sched_fail(object->instance);
        plcb_schedctx_iter_bail(&ctx, ctx.err);
    }
    return plcb_schedctx_return(&ctx);
}

typedef struct {
    plcb_conversion_spec_t spec;
    lcb_storage_t storop;
} my_STOREINFO;

static void
store_argiter_cb(PLCB_schedctx_t *ctx, const char *key, lcb_SIZE nkey,
    SV *doc, SV *options)
{
    STRLEN nvalue = 0;
    char *value = NULL;
    SV *value_sv = NULL;
    lcb_CMDSTORE scmd = ctx->args->u_template.store;
    my_STOREINFO *info = ctx->priv;
    plcb_vspec_t vspec = { 0 };


    LCB_CMD_SET_KEY(&scmd, key, nkey);
    PLCB_args_set(ctx->parent, doc, options, &scmd, ctx, &value_sv, ctx->args->cmd);
    if ((vspec.value = value_sv) == NULL) {
        die("Invalid value!");
    }

    vspec.spec = info->spec;
    plcb_convert_storage(ctx->parent, &vspec);
    if (value_sv == NULL) {
        die("Invalid value!");
    }

    LCB_CMD_SET_VALUE(&scmd, vspec.encoded, vspec.len);
    scmd.flags = vspec.flags;
    scmd.operation = info->storop;
    ctx->err = lcb_store3(ctx->parent->instance, ctx->cookie, &scmd);
    plcb_convert_storage_free(ctx->parent, &vspec);
    if (ctx->err != LCB_SUCCESS) {
        ctx->loop = 0;
    }
}

SV*
PLCB_op_set(PLCB_t *object, PLCB_args_t *args)
{
    PLCB_schedctx_t ctx = { NULL };
    my_STOREINFO info = { 0 };

    plcb_schedctx_init_common(object, args, NULL, &ctx);
    ctx.priv = &info;
    info.storop = plcb_command_to_storop(ctx.cmdbase);
    info.spec = PLCB_CONVERT_SPEC_JSON;

    if (args->cmdopts) {
        PLCB_args_set(object, NULL, (SV*)args->cmdopts, &args->u_template.store,
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
arith_argiter_cb(PLCB_schedctx_t *ctx, const char *key, lcb_SIZE nkey,
    SV *doc, SV *options)
{
    lcb_CMDCOUNTER acmd = { 0 };
    LCB_CMD_SET_KEY(&acmd, key, nkey);

    if (ctx->cmdbase == PLCB_CMD_ARITHMETIC) {
        PLCB_args_arithmetic(ctx->parent, doc, options, &acmd, ctx);
    } else if (ctx->cmdbase == PLCB_CMD_INCR) {
        PLCB_args_incr(ctx->parent, doc, options, &acmd, ctx);
    } else {
        PLCB_args_decr(ctx->parent, doc, options, &acmd, ctx);
    }

    if (!acmd.delta) {
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
PLCB_op_counter(PLCB_t *object, PLCB_args_t *args)
{
    PLCB_schedctx_t ctx = { NULL };
    PLCB_t *obj;
    
    ctx.flags = PLCB_ARGITERf_RAWKEY_OK|PLCB_ARGITERf_RAWVAL_OK|PLCB_ARGITERf_SINGLE_OK;
    plcb_schedctx_init_common(obj, args, NULL, &ctx);
    plcb_schedctx_iter_start(&ctx);
    plcb_schedctx_iter_run(&ctx, arith_argiter_cb);

    if (ctx.err != LCB_SUCCESS) {
        lcb_sched_fail(object->instance);
        plcb_schedctx_iter_bail(&ctx, ctx.err);
    }
    return plcb_schedctx_return(&ctx);
}

static void
remove_argiter_cb(PLCB_schedctx_t *ctx, const char *key, lcb_SIZE nkey,
    SV *doc, SV *opts)
{
    lcb_CMDREMOVE rmcmd = { 0 };
    PLCB_args_remove(ctx->parent, doc, opts, &rmcmd, ctx);
    LCB_CMD_SET_KEY(&rmcmd, key, nkey);
    ctx->err = lcb_remove3(ctx->parent->instance, ctx->cookie, &rmcmd);
    if (ctx->err != LCB_SUCCESS) {
        ctx->loop = 0;
    }
}

SV*
PLCB_op_remove(PLCB_t *object, PLCB_args_t *args)
{
    PLCB_schedctx_t ctx = { NULL };

    ctx.flags = PLCB_ARGITERf_RAWKEY_OK|PLCB_ARGITERf_RAWVAL_OK|PLCB_ARGITERf_SINGLE_OK;
    plcb_schedctx_init_common(object, args, NULL, &ctx);
    plcb_schedctx_iter_start(&ctx);
    plcb_schedctx_iter_run(&ctx, remove_argiter_cb);

    if (ctx.err != LCB_SUCCESS) {
        lcb_sched_fail(object->instance);
        plcb_schedctx_iter_bail(&ctx, ctx.err);
    }

    return plcb_schedctx_return(&ctx);
}

static void
unlock_argiter_cb(PLCB_schedctx_t *ctx, const char *key, lcb_SIZE nkey, SV *doc, SV *opts)
{
    lcb_CMDUNLOCK ucmd = { 0 };
    PLCB_args_unlock(ctx->parent, doc, opts, &ucmd, ctx);
    LCB_CMD_SET_KEY(&ucmd, key, nkey);
    ctx->err = lcb_unlock3(ctx->parent->instance, ctx->cookie, &ucmd);
    if (ctx->err != LCB_SUCCESS) {
        ctx->loop = 0;
    }
}

SV*
PLCB_op_unlock(PLCB_t *object, PLCB_args_t *args)
{
    PLCB_schedctx_t ctx = { NULL };
    plcb_schedctx_init_common(object, args, NULL, &ctx);
    plcb_schedctx_iter_start(&ctx);
    plcb_schedctx_iter_run(&ctx, unlock_argiter_cb);

    if (ctx.err != LCB_SUCCESS) {
        lcb_sched_fail(object->instance);
        plcb_schedctx_iter_bail(&ctx, ctx.err);
    }

    return plcb_schedctx_return(&ctx);
}
