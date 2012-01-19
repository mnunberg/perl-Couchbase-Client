#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'Couchbase::Client' ) || print "Bail out!
";
}

diag( "Testing Couchbase::Client $Couchbase::Client::VERSION, Perl $], $^X" );
