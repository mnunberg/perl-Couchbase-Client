#ifndef PLCB_KWARGS_H_
#define PLCB_KWARGS_H_

typedef enum {

    /* Reference to hash */
    PLCB_ARG_T_HV = 1,

    /* Reference to array */
    PLCB_ARG_T_AV,

    PLCB_ARG_T_SV,

    PLCB_ARG_T_CV,

    PLCB_ARG_T_RV,

    /* Expiration value (UV) */
    PLCB_ARG_T_EXP,

    /* Like an expiration value, but for a 'time_t*' pointer */
    PLCB_ARG_T_EXPTT,

    /* CAS value */
    PLCB_ARG_T_CAS,

    /* 32 bit integer target */
    PLCB_ARG_T_I32,

    /* 64 bit integer target */
    PLCB_ARG_T_I64,

    PLCB_ARG_T_U64,

    /* Boolean value (integer target) */
    PLCB_ARG_T_BOOL,

    /* simple 'int' type */
    PLCB_ARG_T_INT,

    /* String value, (const char**, STRLEN*) */
    PLCB_ARG_T_STRING,

    /* Like a string, but ensure it's not empty */
    PLCB_ARG_T_STRING_NN
} plcb_argtype_t;

typedef struct {
    const char *key;
    size_t nkey;
    plcb_argtype_t type;
    void *value;
    SV *sv;
} plcb_argval_t;

#define PLCB_ARG_K_CAS "cas"
#define PLCB_ARG_K_EXPIRY "exp"
#define PLCB_ARG_K_ARITH_DELTA "delta"
#define PLCB_ARG_K_ARITH_INITIAL "initial"
#define PLCB_ARG_K_ARITH_CREATE "create"
#define PLCB_ARG_K_LOCK "lock_timeout"
#define PLCB_ARG_K_PERSIST "persist_to"
#define PLCB_ARG_K_REPLICATE "replicate_to"

#define PLCB_KWARG(s, tbase, target) \
{ s, sizeof(s)-1, PLCB_ARG_T_##tbase, target }

#define PLCB_ARGS_MAX 10

int plcb_extract_args(HV *hash, plcb_argval_t *values);

typedef struct {
    /* What time is it now? */
    time_t now;

    /* die automatically */
    int autodie;

    /* error message to throw */
    const char *errmsg;
} PLCB_argopts_t;


int PLCB_args_get(PLCB_t *object,
                  SV **args,
                  int nargs,
                  lcb_get_cmd_t *gcmd,
                  PLCB_argopts_t *ao);

int PLCB_args_lock(PLCB_t *object,
                   SV **args,
                   int nargs,
                   lcb_get_cmd_t *gcmd,
                   PLCB_argopts_t *ao);

int PLCB_args_touch(PLCB_t *object,
                    SV **args,
                    int nargs,
                    lcb_touch_cmd_t *tcmd,
                    PLCB_argopts_t *ao);

int PLCB_args_remove(PLCB_t *object,
                     SV **args,
                     int nargs,
                     lcb_remove_cmd_t *rcmd,
                     PLCB_argopts_t *ao);

int PLCB_args_arithmetic(PLCB_t *object,
                         SV **args,
                         int nargs,
                         lcb_arithmetic_cmd_t *acmd,
                         PLCB_argopts_t *ao);

int PLCB_args_incr(PLCB_t *object,
                   SV **args,
                   int nargs,
                   lcb_arithmetic_cmd_t *acmd,
                   PLCB_argopts_t *ao);

int PLCB_args_decr(PLCB_t *object,
                   SV **args,
                   int nargs,
                   lcb_arithmetic_cmd_t *acmd,
                   PLCB_argopts_t *ao);


int PLCB_args_unlock(PLCB_t *object,
                     SV **args,
                     int nargs,
                     lcb_unlock_cmd_t *ucmd,
                     PLCB_argopts_t *ao);

int PLCB_args_set(PLCB_t *object,
                  SV **args,
                  int nargs,
                  lcb_store_cmd_t *scmd,
                  PLCB_argopts_t *ao);

int PLCB_args_cas(PLCB_t *object,
                  SV **args,
                  int nargs,
                  lcb_store_cmd_t *scmd,
                  PLCB_argopts_t *ao);

#endif /* PLCB_KWARGS_H_ */
