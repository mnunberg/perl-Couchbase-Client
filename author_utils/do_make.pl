#!/usr/bin/env perl
use strict;
use warnings;
use Getopt::Long;

GetOptions(
    'p|prefix=s' => \my $Prefix,
    'cc=s' => \my $CC,
    'j=i' => \my $JOBS,
    'w|warnings' => \my $WALL
);

$Prefix ||= "/sources/libcouchbase/inst";

system("make distclean");

my $cmd = "$^X Makefile.PL ";
$cmd .= sprintf("--incpath='-I%s/include' ", $Prefix);
$cmd .= sprintf("--libpath='-L%s/lib' ", $Prefix);
if ($CC) {
    $cmd .= "CC=$CC ";
}

if ($WALL) {
    $cmd .= "OPTIMIZE='-Wall -ggdb3'";
}

system($cmd);

my $mcmd = "make ";
if ($JOBS) {
    $mcmd .= "-j$JOBS";
}

system($mcmd);
