#include "perl-couchbase.h"
#include <libcouchbase/api3.h>

static int
cmd_to_storop(int cmd)
{
    if (cmd == PLCB_CMD_ADD) { return LCB_ADD; }
    if (cmd == PLCB_CMD_SET) { return LCB_SET; }
    if (cmd == PLCB_CMD_REPLACE) { return LCB_REPLACE; }
    if (cmd == PLCB_CMD_APPEND) { return LCB_APPEND; }
    if (cmd == PLCB_CMD_PREPEND) { return LCB_PREPEND; }
    abort();
    return -1;
}

static void
key_from_so(plcb_SINGLEOP *so, lcb_CMDBASE *cmd)
{
    const char *key;
    lcb_SIZE nkey;

    SV **tmpsv = av_fetch(so->docav, PLCB_RETIDX_KEY, 0);
    if (!tmpsv) {
        die("Cannot pass document without key");
    }

    plcb_get_str_or_die(*tmpsv, key, nkey, "Invalid key");
    LCB_CMD_SET_KEY(cmd, key, nkey);
}

SV *
PLCB_op_get(PLCB_t *object, plcb_SINGLEOP *opinfo)
{
    lcb_error_t err = LCB_SUCCESS;
    lcb_CMDGET gcmd = { 0 };

    PLCB_args_get(object, opinfo, &gcmd);
    key_from_so(opinfo, (lcb_CMDBASE*)&gcmd);
    err = lcb_get3(object->instance, opinfo->cookie, &gcmd);
    return PLCB_args_return(opinfo, err);
}

SV*
PLCB_op_set(PLCB_t *object, plcb_SINGLEOP *opinfo)
{
    lcb_error_t err = LCB_SUCCESS;
    plcb_DOCVAL vspec = { 0 };
    lcb_CMDSTORE scmd = { 0 };

    key_from_so(opinfo, (lcb_CMDBASE *)&scmd);
    PLCB_args_set(object, opinfo, &scmd, &vspec);
    vspec.spec = PLCB_CF_JSON;

    plcb_convert_storage(object, opinfo->docav, &vspec);
    if (vspec.value == NULL) {
        die("Invalid value!");
    }

    LCB_CMD_SET_VALUE(&scmd, vspec.encoded, vspec.len);

    scmd.flags = vspec.flags;
    scmd.operation =  cmd_to_storop(opinfo->cmdbase);

    err = lcb_store3(object->instance, opinfo->cookie, &scmd);
    plcb_convert_storage_free(object, &vspec);
    return PLCB_args_return(opinfo, err);
}

SV*
PLCB_op_counter(PLCB_t *object, plcb_SINGLEOP *opinfo)
{
    lcb_CMDCOUNTER ccmd = { 0 };
    lcb_error_t err = LCB_SUCCESS;
    
    key_from_so(opinfo, (lcb_CMDBASE *)&ccmd);
    PLCB_args_arithmetic(object, opinfo, &ccmd);
    err = lcb_counter3(object->instance, opinfo->cookie, &ccmd);
    return PLCB_args_return(opinfo, err);
}

SV*
PLCB_op_remove(PLCB_t *object, plcb_SINGLEOP *opinfo)
{
    lcb_CMDREMOVE rcmd = { 0 };
    lcb_error_t err = LCB_SUCCESS;

    key_from_so(opinfo, &rcmd);
    PLCB_args_remove(object, opinfo, &rcmd);
    err = lcb_remove3(object->instance, opinfo->cookie, &rcmd);
    return PLCB_args_return(opinfo, err);
}

SV*
PLCB_op_unlock(PLCB_t *object, plcb_SINGLEOP *opinfo)
{
    lcb_CMDUNLOCK ucmd = { 0 };
    lcb_error_t err = LCB_SUCCESS;

    key_from_so(opinfo, &ucmd);
    PLCB_args_unlock(object, opinfo, &ucmd);
    err = lcb_unlock3(object->instance, opinfo->cookie, &ucmd);
    return PLCB_args_return(opinfo, err);
}
