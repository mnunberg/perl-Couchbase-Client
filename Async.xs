MODULE = Couchbase::Client PACKAGE = Couchbase::Client::Async PREFIX = PLCBA_

SV *
PLCBA_construct(pkg, options)
    const char *pkg
    AV *options
    
void
PLCBA_connect(self)
    SV* self

void
PLCBA_HaveEvent(pkg, flags, opaque)
    const char pkg
    short flags
    SV *opaque
    
void
PLCBA_request(self, cmd, reqtype, callcb, cbdata, cbtype, params)
    SV *self
    int cmd
    int reqtype
    SV *callcb
    SV *cbdata
    int cbtype
    AV *params
