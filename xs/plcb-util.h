#ifndef PLCB_UTIL_H_
#define PLCB_UTIL_H_

/* This file contains various conversion functions and macros */

/*this stuff converts from SVs to int64_t (signed and unsigned) depending
 on the perl*/

/*XXX:
12:54 < LeoNerd> mordy: Namely,   my ( $hi, $lo ) = unpack "L> L>", $packed_64bit;
                 my $num = Math::BigInt->new( $hi ); $num >>= 32; $num |= $lo;
                 return $num;
12:55 < mordy> what about vice versa? or would i change my C interface to accept 2
               32 bit integers and piece them back together there?
12:55 < LeoNerd> mordy: That might be simplest.
*/

#ifdef PLCB_PERL64
#define plcb_sv_to_u64(sv) SvUV(sv)
#define plcb_sv_to_64(sv) (int64_t)(plcb_sv_to_u64(sv))
#define plcb_sv_from_u64(sv, num) (sv_setuv(sv, num))
#define plcb_sv_from_u64_new(nump) newSVuv( (*nump) )

#define plcb_cas_from_sv(sv, cas_p) \
    (SvIOK(sv)) \
    ? cas_p = (uint64_t*)&(SvIVX(sv)) \
    : (uint64_t*)die("Expected valid (UV) cas. IOK not true")

#else

static uint64_t plcb_sv_to_u64(SV *in)
{
    char *sv_blob;
    STRLEN blob_len;
    uint64_t ret;
    
    if (SvIOK(in)) {
        /*Numeric*/
        return SvUV(in);
    }
    
    sv_blob = SvPV(in, blob_len);

    if (blob_len != 8) {
        die("expected 8-byte data string. Got %d", (int)blob_len);
    }

    ret = *(uint64_t*)sv_blob;
    return ret;
}

#define plcb_sv_to_64(sv) ((int64_t)(plcb_sv_to_u64(sv)))

#define plcb_sv_from_u64(sv, num) \
    (sv_setpvn(sv, (const char const*)&(num), 8))

#define plcb_sv_from_u64_new(nump) \
    newSVpv((const char* const)(nump), 8)

/*Extract a packed 8 byte blob from an SV into a CAS value*/

static void plcb_cas_from_sv(SV *sv, uint64_t *cas_p)
{
    STRLEN len;
    *cas_p = *(uint64_t*)SvPV(sv, len);

    if (len == 8) {
        if (!*cas_p) {
            die("Expected 8 byte CAS. Got %d\n", (int)len);
        }

    } else {
        die("CAS Specified, but is NULL");
    }
}

    
#endif /*PLCB_PERL64*/

/*assertively extract a non-null key from an SV, together with its length*/

#define plcb_get_str_or_die(ksv, charvar, lenvar, diespec) \
    (void)(((charvar = SvPV(ksv, lenvar))) \
        ? ( (lenvar) ? charvar : (void*)die("Got zero-length %s", diespec) ) \
        : (void*)die("Got NULL %s", diespec))


#define PLCB_TIME_ABS_OFFSET

#ifdef PLCB_TIME_ABS_OFFSET
#define PLCB_UEXP2EXP(cbexp, uexp, now) \
    cbexp = ((uexp) \
        ? ((now) \
            ? (now + uexp) \
            : (time(NULL)) + uexp) \
        : 0)

#else

/*Memcached protocol states that a time offset greater than 30 days is taken
 to be an epoch time. We hide this from perl by simply generating our own
 epoch time based on the user's time*/

#define PLCB_UEXP2EXP(cbexp, uexp, now) \
    cbexp = ((uexp) \
        ? ((uexp > (30*24*60*60)) \
            ? ((now) \
                ? (now + uexp) \
                : (time(NULL) + uexp)) \
            : uexp) \
        : 0)
#endif

/**
 * Extract the expiry value from an SV
 */

static PERL_UNUSED_DECL UV plcb_exp_from_sv(SV *exp)
{

    UV ret = 0;

    if (SvTYPE(exp) == SVt_NULL) {
        return 0;
    }

    if (SvIOK(exp)) {
        IV expiv = SvIVX(exp);
        if (expiv < 0) {
            die("Expiry cannot be negative");
        }

        ret = expiv;

    } else if (SvPOK(exp)) {
        UV exptype = grok_number(SvPVX(exp), SvCUR(exp), &ret);

        if (!exptype) {
            die("Bad expiry value");
        }

        if (exptype == IS_NUMBER_NEG) {
            die("Expiry cannot be negative");
        }

    } else {
        die("Bad type for expiry");
    }

    return ret;
}


/**
 * These utilities utilize perl's SAVE* functions to automatically do cleanup
 * for buffers that may either live on the stack, or be allocated from the heap.
 * This is useful for exception handling, in which case the buffer is freed when
 * the enclosing (Perl) scope ends.
 */

#define PLCB_STRUCT_MAYBE_ALLOC_SIZED(name, elem_type, nelem) \
    struct name { \
        int allocated; \
        elem_type* bufp; \
        elem_type** backref; \
        elem_type prealloc[nelem]; \
    };

#define PLCB_MAYBE_ALLOC_GENFUNCS(name, elem_type, nelem, modifiers) \
static void \
name ## __plalloc_destroy_func(void *p) { \
    char **chrp = (char**)p; \
    if (*chrp) { \
        Safefree(*chrp); \
        *chrp = NULL; \
    } \
    Safefree(chrp); \
} \
modifiers void \
name ## _init(struct name* buf, size_t nelem_wanted) { \
    if (nelem_wanted <= nelem) { \
        buf->bufp = buf->prealloc; \
        buf->allocated = 0; \
        buf->backref = NULL; \
        return; \
    } \
    Newx(buf->bufp, nelem_wanted, elem_type); \
    Newx(buf->backref, 1, elem_type*); \
    *buf->backref = buf->bufp; \
    buf->allocated = 1; \
    SAVEDESTRUCTOR(name ## __plalloc_destroy_func, buf->backref); \
} \
\
modifiers void \
name ## _cleanup(struct name* buf) { \
    if(!buf->allocated) { \
        return; \
    } \
    Safefree(buf->bufp); \
    buf->bufp = NULL; \
    *buf->backref = NULL; \
}

#define plcb_is_arrayref(sv) (SvROK(sv) && SvTYPE(SvRV(sv)) == SVt_PVAV)

/**
 * Make args from an xsub
 */
#define PLCB_MAKEARGS_XS(args) \
{ \
    int plcb__args_ii; \
    if (items > PLCB_ARGS_MAX) { \
        die("Too many arguments"); \
    } \
    for (plcb__args_ii = 1; plcb__args_ii < items; plcb__args_ii++) { \
        args[plcb__args_ii - 1] = ST(plcb__args_ii); \
    } \
}

#define plcb_makeargs_av(args, av, lenp) \
{ \
    int plcb__args_ii; \
    int plcb__args_max = av_len((av)) + 1; \
    if (plcb__args_max > PLCB_ARGS_MAX) { \
        die("Too many arguments"); \
    } \
    for (plcb__args_ii = 0; plcb__args_ii < plcb__args_max; plcb__args_ii++) { \
        (args)[plcb__args_ii] = *av_fetch((av), plcb__args_ii, 0); \
    } \
    *(lenp) = plcb__args_max; \
}


#define PLCB_APPEND_SANITY(cmd, sv) \
        if (SvROK((sv)) && SvTYPE(SvRV((sv))) != SVt_PVHV && \
                (cmd == PLCB_CMD_APPEND || cmd == PLCB_CMD_PREPEND)) { \
            die("Cannot append/prepend a reference"); \
        }


#define plcb_is_simple_string(sv) ( SvPOK(sv) != 0 && SvROK(sv) == 0 )

/* Handy types for XS */
/* for easy passing */
typedef struct {
    struct PLCB_st *ptr;
    SV *sv;
} PLCB_XS_OBJPAIR_t;

typedef struct {
    SV *origsv;
    char *base;
    STRLEN len;
} PLCB_XS_STRING_t;

typedef PLCB_XS_STRING_t PLCB_XS_STRING_NONULL_t;


#endif /* PLCB_UTIL_H_ */
