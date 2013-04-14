#include "perl-couchbase.h"

MODULE = Couchbase::Client_iterator PACKAGE = Couchbase::Client::Iterator

PROTOTYPES: DISABLE

void
next(PLCB_iter_t *iterator)

    PREINIT:
    SV *ksv = NULL, *retav = NULL;
    PPCODE:
    plcb_multi_iterator_next(iterator, &ksv, &retav);

    if (GIMME_V == G_ARRAY) {
        if (ksv) {
            EXTEND(SP, 2);
            PUSHs(sv_2mortal(ksv));
            PUSHs(sv_2mortal(retav));
        }

    } else {
        EXTEND(SP, 1);
        PUSHs(sv_2mortal(newSViv(iterator->remaining)));
    }

IV
remaining(PLCB_iter_t *iterator)

    CODE:
    RETVAL = iterator->remaining;
    OUTPUT: RETVAL

SV*
error(PLCB_iter_t *iterator)

    CODE:
    if (iterator->remaining != PLCB_ITER_ERROR) {
        RETVAL = &PL_sv_undef;

    } else {
        RETVAL = newRV_noinc((SV*)iterator->error_av);
    }
    OUTPUT: RETVAL


void
DESTROY(PLCB_iter_t *iterator)
    CODE:
    plcb_multi_iterator_cleanup(iterator);
