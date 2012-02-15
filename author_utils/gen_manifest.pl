#!/usr/bin/perl
use strict;
use warnings;
use Dir::Self;
use lib __DIR__;

my $config = do 'PLCB_Config.pm' or die $@;

my $vbucket_release = $config->{LIBVBUCKET_RELEASE};
my $couchbase_release = $config->{LIBCOUCHBASE_RELEASE};

open my $infh, "<", "MANIFEST.in";
open my $outfh, ">", "MANIFEST";

foreach my $line (<$infh>) {
    next unless $line;
    $line =~ s/__LIBCOUCHBASE_RELEASE__/$couchbase_release/g;
    $line =~ s/__LIBVBUCKET_RELEASE__/$vbucket_release/g;
    print $outfh $line;
}
