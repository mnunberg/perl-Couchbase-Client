package Couchbase::IO::Event;
use strict;
use warnings;
use Couchbase::IO::Constants;
use Class::XSAccessor::Array {
    accessors => {
        dupfh => COUCHBASE_EVIDX_DUPFH,
        data => COUCHBASE_EVIDX_PLDATA,
        fileno => COUCHBASE_EVIDX_FD,
        flags => COUCHBASE_EVIDX_WATCHFLAGS
    }
};

sub is_timer { $_[0]->[COUCHBASE_EVIDX_TYPE] == COUCHBASE_EVTYPE_TIMER }
sub is_io { $_[0]->[COUCHBASE_EVIDX_TYPE] == COUCHBASE_EVTYPE_IO }
1;
