package Couchbase::Cluster;
use Couchbase::Bucket;
use Class::XSAccessor accessors => [qw(uribase)];

sub new {
    my ($pkg, $uribase) = @_;
    bless my $rv, $pkg;
    $rv->uribase($uribase);
    return $rv;
}

1;
