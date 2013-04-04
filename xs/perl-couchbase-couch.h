#ifndef PERL_COUCHBASE_H_
#error "Include perl-couchbase.h directly"
#endif

#ifndef PERL_COUCHBASE_VIEWS_H_
#define PERL_COUCHBASE_VIEWS_H_

#define PLCB_JSON_CLASSNAME "JSON::XS"

#define PLCB_COUCH_HANDLE_INFO_CLASSNAME "Couchbase::Couch::HandleInfo"

/**
 * Let's try to simulate DBI-like semantics for views. In this case,
 * we will consider a design document and a view as 'statement handles',
 * and allow for iteration over them without an explicit callback interface.
 *
 * my $design = $cbo->design_get("blogs");
 * my $view = $design->view("recent_comments");
 *
 * # $vh is a 'statement handle', the parameters would be query parameters
 * $vh = $view->execute(foo => "bar", count => 12); #etc.
 * 
 *
   while (my $doc = $vh->fetch_one()) {
        if ($doc->{whatever}) {
            # stop iterating
            $vh->cancel(); 
        }
   }
   
   # check errors:
   if (!$vh->is_ok) {
    ....
   }
   
   my @docs = $vh->fetch_all();
   # check for errors, as normal
   
   
   # View and Design documents will be accessible as a normal perl hash,
   # with magical methods called on them using the sv_magic* subsystem.
   
  
 * Implementing this is somewhat difficult. What will really happen is that
 * all these view objects will maintain a handle to the Couchbase::Client object.
 *
 * We will expose something similar to an io->run_event_loop/io->stop_event_loop.
 * Internally the view will implement a callback function as well as maintain
 * some private data (via magic) possibly containing a not-yet-parsed JSON
 * buffer. The internal C level callback will invoke the view-level callback
 * function (which shall inspect to see if it has at least one new object, or
 * an error).
 *
 * Much of the magic will be on the implicit 'statement handle', which should
 * implement these methods:
 *      data_callback($object, $data);
 *      
 * 
 * We will extend the standard 'return' object to accomodate extra temporary
 * Couch status fields.
 *
 * Specifically, the 'handle' will be structured as follows:
 *
 * Couchbase::RequestHandle=SCALAR (IV)
 *
 * IV is a pointer to C data:
 *      C Object:
 *          Current libcouchbase request
 *          Request parameters and status flags
 *
 *          Pointer to AV:
 *              Couchbase::RequestHandle::PLData=ARRAY
 *               subclass of Couchbase::Client::Return
 *
 *               Completion CV
 *               Data CV
 *               Couchbase::Client SV
 *               Status
 *               User Data (most likely a JSON::XS object)
 *
 * The object shall contain an accessor upon which to access the 'raw'
 * array and other such fields.
 *
 * Particularly, there shall be a set of callbacks, as well as user data, available
 *
 *
 *
**/


/* Extended fields for Couch handles */
enum {
    PLCB_COUCHIDX_HTTP = PLCB_RETIDX_CAS,
    PLCB_COUCHIDX_UDATA = PLCB_RETIDX_MAX,
    PLCB_COUCHIDX_CBO,
    
    PLCB_COUCHIDX_CALLBACK_DATA,
    PLCB_COUCHIDX_CALLBACK_COMPLETE,
    
    PLCB_COUCHIDX_PATH,
    PLCB_COUCHIDX_ERREXTRA,
    PLCB_COUCHIDX_ROWCOUNT,
    PLCB_COUCHIDX_MAX
};

/* Extended fields for Couch Rows (view results, design documents) */
enum {
    /* The parent object.. */
    PLCB_ROWIDX_CBO = PLCB_RETIDX_MAX,
    PLCB_ROWIDX_DOCID,
    PLCB_ROWIDX_REV
};

typedef enum {
    /* Whether to use incremental data callbacks */
    PLCB_COUCHREQf_CHUNKED = 1 << 0,
    
    /* Set in order to gather status codes etc. */
    PLCB_COUCHREQf_INITIALIZED = 1 << 1,
    
    /* Whether this request is active */
    PLCB_COUCHREQf_ACTIVE = 1 << 2,
    
    /* Whether this request has terminated/ (cancelled or failed) */
    PLCB_COUCHREQf_TERMINATED = 1 << 3,

    /* Whether this request has an error */
    PLCB_COUCHREQf_ERROR = 1 << 4,

    /* Set by the iterator when we have enough data to suspend the event loop */
    PLCB_COUCHREQf_STOPITER = 1 << 5,

    /* This flag is set once stop_event_loop is called, and is
     * used to avoid multiple calls to evloop_wait_unref()
     */
    PLCB_COUCHREQf_STOPITER_NOOP = 1 << 6
} plcb_couch_reqflags_t;


typedef struct {    
    /* Couchbase::Client::Return-like object to store some status
      bits */
    AV *plpriv;
    
    lcb_http_request_t lcb_request;
    plcb_couch_reqflags_t flags;
    
    PLCB_t *parent;

    /* Weak reference to ourselves, so we can pass it to the callbacks */
    SV *self_rv;
} PLCB_couch_handle_t;


void plcb_couch_callbacks_setup(PLCB_t *object);

/**
 * Create a new handle. stash is the subclass in which the handle
 * should be blessed, cbo_sv is a Couchbase::Client object (whose reference
 * count will be incremented) and cbo is the C-level parent object
 */
SV *plcb_couch_handle_new(HV *stash, SV *cbo_sv, PLCB_t *cbo);

void plcb_couch_handle_free(PLCB_couch_handle_t *handle);

/* Non-chunked */
void plcb_couch_handle_execute_all(PLCB_couch_handle_t *handle,
                                   lcb_http_method_t method,
                                   const char *path, size_t npath,
                                   const char *body, size_t nbody);

/* Chunked, prepare the handle */
void plcb_couch_handle_execute_chunked_init(PLCB_couch_handle_t *handle,
                                            lcb_http_method_t method,
                                            const char *path, size_t npath,
                                            const char *body, size_t nbody);


/* Chunked, wait until callback signal is done */
int plcb_couch_handle_execute_chunked_step(PLCB_couch_handle_t *handle);

/* Cancel a request. If the request is not yet active then nothing happens */
void plcb_couch_handle_finish(PLCB_couch_handle_t *handle);


#endif /* PERL_COUCHBASE_VIEWS_H_ */
