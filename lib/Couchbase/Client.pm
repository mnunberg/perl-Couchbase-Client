warn "Loading this file is deprecated. Use Couchbase::Cluster/Couchbase::Bucket";

package Couchbase::Client;
use Couchbase::Cluster;
use Couchbase::Bucket;

sub new {
    shift;
    return Couchbase::Bucket->new(@_);
}

1;
