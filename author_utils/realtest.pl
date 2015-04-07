#!/usr/bin/env perl
use strict;
use warnings;

my %Config = (
    bucket => "default",
    username => "Administrator",
    password => "123456",
    memd_port => 11212,
    server => "localhost:8091"
);

my @confpairs;
while ( my ($k,$v) = each %Config ) {
    push @confpairs, "$k=$v";
}

my $confstr = join(",", @confpairs);
$ENV{PLCB_TEST_REAL_SERVER} = $confstr;
my @execline = ($^X, "./author_utils/testone.pl", @ARGV);

if ($ENV{VALGRIND}) {
    unshift @execline, split(' ', $ENV{VALGRIND});
}

exec @execline;

