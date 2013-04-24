/**
 * This header file defines flexible command constants which we use
 * throughout the file. These are different than the constants used
 * in libcouchbase and memcached, particularly they provide quickly
 * accessible attributes about the command
 */


#ifndef PLCB_COMMANDS_H_
#define PLCB_COMMANDS_H_

#ifndef PERL_COUCHBASE_H_
#error "Include perl-couchbase.h first"
#endif


#define PLCB_COMMANDf_MULTI 0x100
#define PLCB_COMMANDf_COUCH 0x200
#define PLCB_COMMANDf_ITER 0x400
#define PLCB_COMMANDf_SINGLE 0x800

/* Mask for only the command itself */
#define PLCB_COMMAND_MASK 0xff
#define PLCB_COMMAND_MASK_STRIP 0x1f

#define PLCB_COMMAND_EXTRA_MASK \
    (PLCB_COMMANDf_MULTI|PLCB_COMMANDf_COUCH|PLCB_COMMANDf_ITER)


#define X_STORAGE \
    X(SET, 0) \
    X(ADD, 0) \
    X(REPLACE, 0) \
    \
    X(APPEND, 0) \
    X(PREPEND, 0)

#define X_MISC \
    X(REMOVE, 0) \
    X(GET, 0) \
    X(LOCK, 0) \
    X(UNLOCK, 0) \
    X(TOUCH, 0) \
    X(INCR, 0) \
    X(DECR, 0) \
    X(ARITHMETIC, 0) \
    X(GAT, 0) \
    \
    X(CAS, 0) \
    \
    X(STATS, 0) \
    X(FLUSH, 0) \
    X(VERSION, 0) \


#define X_ALL \
    X(NULL, 0) \
    X_STORAGE \
    X_MISC


/* Set up a basic incremental enumeration */
enum {
    #define X(v, prop) PLCB__CMDPRIV_ ## v,
    X_ALL
    #undef X
};


enum {
    #define X(v, prop) \
        PLCB_CMD_ ## v = (PLCB__CMDPRIV_ ## v | prop), \
        PLCB_CMD_MULTI_ ## v = (PLCB_CMD_ ## v | PLCB_COMMANDf_MULTI), \
        PLCB_CMD_COUCH_ ## v = (PLCB_CMD_ ## v | PLCB_COMMANDf_COUCH), \
        PLCB_CMD_MULTI_COUCH_ ## v = \
            (PLCB_CMD_ ## v | PLCB_COMMANDf_MULTI|PLCB_COMMANDf_COUCH), \
        PLCB_CMD_ITER_ ## v = (PLCB_CMD_ ## v | PLCB_COMMANDf_ITER),
            
    
    X_ALL
    #undef X
};

static lcb_storage_t PLCB__StorageMap[] = {
    #define X(v, prop) \
        [PLCB__CMDPRIV_ ## v] = LCB_ ## v,
    X_STORAGE
    #undef X
};

static PERL_UNUSED_DECL lcb_storage_t
plcb_command_to_storop(int cmd)
{
    int cmd_base = cmd & PLCB_COMMAND_MASK_STRIP;
    if (cmd_base == PLCB__CMDPRIV_CAS) {
        return LCB_SET;
    }
    return PLCB__StorageMap[cmd_base];
}    

#endif /* PLCB_COMMANDS_H_ */

