#!/usr/bin/perl
use strict;
use warnings;
use Cwd qw(getcwd);
use File::Basename qw(fileparse);
use Log::Fu;
use File::Spec;
use Dir::Self;
use Config;
use File::Path qw(mkpath);

use lib __DIR__;
use PLCB_ConfUtil;

require 'PLCB_Config.pm';

my $plcb_conf = do 'PLCB_Config.pm' or die "Cannot find configuration";

sub runcmd {
    my $cmd = join(" ", @_);
    system($cmd . " > /dev/null") == 0 or die "$cmd failed";
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

my $TOPLEVEL = PLCB_ConfUtil::get_toplevel_dir();
my $INST_DIR = PLCB_ConfUtil::get_inst_dir();

chdir $TOPLEVEL;
mkpath($INST_DIR);

log_info("We're in $TOPLEVEL now");
my @COMMON_OPTIONS = (
"--prefix=$INST_DIR",
qw(
--silent
--disable-shared 
--enable-static 
--without-docs)
);

runcmd("tar xf $MEMCACHED_H_TARBALL -C $INST_DIR");

$ENV{CPPFLAGS} .= ' -fPIC ';
#build libvbucket first:
{
    chdir tarball_2_dir($LIBVBUCKET_TARBALL);
    if(!-e 'Makefile') {
        runcmd("./configure", @COMMON_OPTIONS);
        log_info("Configured libvbucket");
    }
    
    runcmd("make");
    log_info("build libvbucket");
    runcmd("make install");
    log_info("installed libvbucket");
    runcmd("make check");
    log_info("tested libvbucket");    
}

{
    chdir $TOPLEVEL;
    chdir tarball_2_dir($LIBCOUCHBASE_TARBALL);
    $ENV{CPPFLAGS} .= " -I".File::Spec->catfile($INST_DIR, "include");
    $ENV{LDFLAGS} .= " -lm -L".File::Spec->catfile($INST_DIR, "lib");
    log_info("CPPFLAGS:", $ENV{CPPFLAGS});
    log_info("LDFLAS:", $ENV{LDFLAGS});
    
    my @libcouchbase_options = (
        @COMMON_OPTIONS,
        "--disable-tools",
        "--enable-embed-libevent-plugin",
    );
    
    my $have_java = eval { runcmd("java", "-version"); 1; };
    my $mockpath = File::Spec->catfile(
        __DIR__, 't', 'tmp', 'CouchbaseMock.jar');
    
    if($have_java && -e $mockpath) {
        push @libcouchbase_options, '--with-couchbase-mock='.$mockpath;
    } else {
        push @libcouchbase_options, '--disable-couchbasemock';
    }
    
    if(!-e 'Makefile') {
        runcmd("./configure", @libcouchbase_options);
    }
    runcmd("make install check -s");
}

#Write a little file about where our stuff is located:
