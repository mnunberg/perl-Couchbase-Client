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


#define PLCB_COMMANDf_MULTI 0x80
#define PLCB_COMMANDf_COUCH 0x100
#define PLCB_COMMANDf_ITER 0x200

#define PLCB_COMMANDf_NEEDSKEY 0x20
#define PLCB_COMMANDf_NEEDSTRVAL 0x40
#define PLCB_COMMANDf_MUTATE_CLEAN (0x80|0x40)

/* Mask for only the command itself */
#define PLCB_COMMAND_MASK 0xff
#define PLCB_COMMAND_MASK_STRIP 0x1f


#define PLCB_COMMAND_PROPMASK \
    (PLCB_COMMANDf_NEEDSKEY| \
    PLCB_COMMANDf_NEEDSTRVAL |\
    PLCB_COMMANDf_MUTATE_CLEAN)

#define PLCB_COMMAND_EXTRA_MASK \
    (PLCB_COMMANDf_MULTI|\
    PLCB_COMMANDf_COUCH| \
    PLCB_COMMANDf_ITER)


#define X_STORAGE \
    X(SET, PLCB_COMMANDf_NEEDSKEY|PLCB_COMMANDf_MUTATE_CLEAN) \
    X(ADD, PLCB_COMMANDf_NEEDSKEY|PLCB_COMMANDf_MUTATE_CLEAN) \
    X(REPLACE, PLCB_COMMANDf_NEEDSKEY|PLCB_COMMANDf_MUTATE_CLEAN) \
    \
    X(APPEND, PLCB_COMMANDf_NEEDSKEY|PLCB_COMMANDf_NEEDSTRVAL) \
    X(PREPEND, PLCB_COMMANDf_NEEDSKEY|PLCB_COMMANDf_NEEDSTRVAL)

#define X_MISC \
    X(REMOVE, PLCB_COMMANDf_NEEDSKEY) \
    X(GET, PLCB_COMMANDf_NEEDSKEY) \
    X(TOUCH, PLCB_COMMANDf_NEEDSKEY) \
    X(INCR, PLCB_COMMANDf_NEEDSKEY) \
    X(DECR, PLCB_COMMANDf_NEEDSKEY) \
    X(ARITHMETIC, PLCB_COMMANDf_NEEDSKEY) \
    X(GAT, PLCB_COMMANDf_NEEDSKEY) \
    \
    X(CAS, PLCB_COMMANDf_NEEDSKEY|PLCB_COMMANDf_MUTATE_CLEAN) \
    \
    X(STATS, 0) \
    X(FLUSH, 0) \
    X(VERSION, 0) \


#define X_ALL \
    X_STORAGE \
    X_MISC


/* Set up a basic incremental enumeration */
enum {
    #define X(v, prop) \
        PLCB__CMDPRIV_ ## v,
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

#define plcb_command_needs_key(cmd) ( (cmd) & PLCB_COMMANDf_NEEDSKEY )

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

