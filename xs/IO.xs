#include "perl-couchbase.h"

MODULE = Couchbase::IO PACKAGE = Couchbase::IO    PREFIX = plcbio_

PROTOTYPES: DISABLE

SV *
plcbio_new(const char *pkg, SV *options)
    CODE:
    (void)pkg;
    RETVAL = PLCB_ioprocs_new(options);
    OUTPUT: RETVAL

SV *
plcbio_data(plcb_IOPROCS *io, ...)
    CODE:
    if (items == 2) {
        SvREFCNT(io->userdata);
        io->userdata = ST(1);
        SvREFCNT_inc(io->userdata);
        RETVAL = &PL_sv_undef;
    } else {
        if (io->userdata) {
            RETVAL = io->userdata;
        } else {
            RETVAL = &PL_sv_undef;
        }
    }
    SvREFCNT_inc(RETVAL);
    OUTPUT: RETVAL


MODULE = Couchbase::IO PACKAGE = Couchbase::IO::Event   PREFIX = plcbio_
void
plcbio_dispatch(plcb_EVENT *event, int flags)
    CODE:
    event->lcb_handler(event->fd, flags, event->lcb_arg);
