#!/usr/bin/perl
use strict;
use warnings;
use Cwd qw(getcwd);
use File::Basename qw(fileparse);
use Log::Fu;
use File::Slurp qw(read_file write_file);
use File::Spec;
use Dir::Self;
use Config;
use Getopt::Long;

use lib __DIR__;

require 'PLCB_Config.pm';

my $plcb_conf = do 'PLCB_Config.pm' or die "Cannot find configuration";

sub runcmd {
    my $cmd = join(" ", @_);
    system($cmd) == 0 or die "$cmd failed";
}

#Figure out various ways to get a tarball



my $LIBVBUCKET_TARBALL = $plcb_conf->{LIBVBUCKET_RELEASE};
my $LIBCOUCHBASE_TARBALL = $plcb_conf->{LIBCOUCHBASE_RELEASE};

unless ($LIBCOUCHBASE_TARBALL && $LIBVBUCKET_TARBALL) {
    die("Cannot find appropriate tarball names. Please edit PLCB_Config.pm");
}

$LIBVBUCKET_TARBALL = "libvbucket-$LIBVBUCKET_TARBALL.tar.gz";
$LIBCOUCHBASE_TARBALL = "libcouchbase-$LIBCOUCHBASE_TARBALL.tar.gz";

my $MEMCACHED_H_TARBALL = "memcached-headers.tar.gz";

sub tarball_2_dir {
    my $tarball = shift;
    runcmd("tar xf $tarball");
    my $filename = fileparse($tarball, qr/\.tar\..*/);
    return $filename;
}

chdir 'src';
my $TOPLEVEL = getcwd();
my $INST_DIR = File::Spec->catfile($TOPLEVEL, 'inst');
log_info("We're in $TOPLEVEL now");
my @COMMON_OPTIONS = (
"--prefix=$INST_DIR",
qw(
--disable-shared 
--enable-static 
--without-docs)
);

runcmd("tar xf $MEMCACHED_H_TARBALL");

$ENV{CPPFLAGS} .= ' -fPIC ';
#build libvbucket first:
{
    chdir tarball_2_dir($LIBVBUCKET_TARBALL);
    if(!-e 'Makefile') {
        runcmd("./configure", @COMMON_OPTIONS);
    }
    runcmd("make install check -sj20");
}

{
    chdir $TOPLEVEL;
    chdir tarball_2_dir($LIBCOUCHBASE_TARBALL);
    $ENV{CPPFLAGS} .= "-I".File::Spec->catfile($TOPLEVEL, "include");
    $ENV{CPPFLAGS} .= " -I".File::Spec->catfile($INST_DIR, "include");
    $ENV{LDFLAGS} .= " -lm -L".File::Spec->catfile($INST_DIR, "lib");
    log_info("CPPFLAGS:", $ENV{CPPFLAGS});
    log_info("LDFLAS:", $ENV{LDFLAGS});
    if(!-e 'Makefile') {
        runcmd("./configure", @COMMON_OPTIONS, "--disable-tools",
                "--enable-embed-libevent-plugin");
    }
    runcmd("make install check -sj20");
}

#Write a little file about where our stuff is located:
