#!/usr/bin/perl
use strict;
use warnings;
use blib;
use Dir::Self;
use lib __DIR__ . "../lib";
use lib __DIR__ . "../";

# This will execute a single test from the suite, via regex. This
# might be a bit broken at times

$Log::Fu::LINE_PREFIX = '#';

my $config = do 'PLCB_Config.pm';
use Couchbase::Test::Common;
my $TEST_PORT;

Couchbase::Test::Common->Initialize(
    jarfile => __DIR__ . "/../t/tmp/CouchbaseMock.jar",
    nodes => 2,
    buckets => [{name => "default", type => "memcache"}],
);

use Couchbase::Test::ClientSync;
use Couchbase::Test::Async;
use Couchbase::Test::Settings;
use Couchbase::Test::Interop;
use Couchbase::Test::Netfail;
use Couchbase::Test::Views;

$ENV{TEST_METHOD} = shift @ARGV;
Test::Class->runtests();

