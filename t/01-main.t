#!/usr/bin/perl
use Dir::Self;
use lib __DIR__ . "../lib";
use lib __DIR__ . "../";

$Log::Fu::LINE_PREFIX = '#';

my $config = do 'PLCB_Config.pm';
use Couchbase::Test::Common;
my $TEST_PORT;

Couchbase::Test::Common->Initialize(
    url => $config->{COUCHBASE_MOCK_JARURL},
    dir => __DIR__ . "/tmp",
    port => 8092,
    nodes => 2,
);

use Couchbase::Test::ClientSync;
Test::Class->runtests();
