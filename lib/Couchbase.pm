package Couchbase;
our $VERSION = '2.0.0_1';
1;

BEGIN {
    require XSLoader;
    our $VERSION = '2.0.0_1';
    XSLoader::load('Couchbase', $VERSION);
}

use Couchbase::_GlueConstants;
use Couchbase::Bucket;

our @ERRMAP = ();

1;

__END__

=head1 NAME

Couchbase - Perl client for L<Couchbase|http://www.couchbase.com>
