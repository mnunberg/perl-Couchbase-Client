#!/usr/bin/perl
use strict;
use warnings;
use Cwd qw(getcwd);
use File::Basename qw(fileparse);
use Log::Fu;
use File::Spec;
use Dir::Self qw(:static);
use Config;
use File::Path qw(mkpath rmtree);
use Getopt::Long;
use Archive::Extract;

GetOptions(
    "build-prefix=s" => \my $BuildPrefix,
    "install-prefix=s" => \my $InstallPrefix,
    'env-cppflags=s' => \my $ENV_CPPFLAGS,
    'env-ldflags=s' => \my $ENV_LDFLAGS,
    'env-libs=s'  => \my $ENV_LIBS,
    'rpath=s'     => \my $RPATH,
    'have-java'   => \my $HAVE_JAVA,
    'no-tests'    => \my $NO_RUN_TESTS,
);

use lib __DIR__;
use PLCB_ConfUtil;

require 'PLCB_Config.pm';

my $plcb_conf = do 'PLCB_Config.pm' or die "Cannot find configuration";

my $BUILD_SILENT = "> /dev/null";
if($ENV{PLCB_BUILD_NOISY}) {
    $BUILD_SILENT = "";
}

my $RUN_TESTS = 1;

if(exists $ENV{PLCB_RUN_TESTS}) {
    $RUN_TESTS = $ENV{PLCB_RUN_TESTS};
}

if ($NO_RUN_TESTS) {
    print STDERR "Test execution disabled from command line\n";
    $RUN_TESTS = 0;
}

if($^O =~ /solaris/) {
    print STDERR "Tests disabled on solaris\n";
    $RUN_TESTS = 0;
}

my %DEPS = map {  ( $_, $_ ) } @ARGV;

sub runcmd {
    my $cmd = join(" ", @_);
    print STDERR "[EXECUTING]:\n\t$cmd\n";
    unless(system($cmd . " $BUILD_SILENT") == 0) {
        print STDERR "Command $cmd failed\n";
        printf STDERR ("CPPFLAGS=%s\nLDFLAGS=%s\n", $ENV{CPPFLAGS}, $ENV{LDFLAGS});
        printf STDERR ("LD_RUN_PATH=%s\n", $ENV{LD_RUN_PATH});
        printf STDERR ("LIBS=%s\n", $ENV{LIBS});
        printf STDERR ("LDFLAGS", $ENV{LDFLAGS});
        die "";
    }
}

sub lib_2_tarball {
    my $lib = shift;
    my $release = $plcb_conf->{uc($lib) . "_RELEASE"};
    my $name = "$lib-$release.tar.gz";
}

sub tarball_2_dir {
    my $tarball = shift;
    my $ae = Archive::Extract->new(archive => $tarball);
    $ae->extract();
    my $filename = fileparse($tarball, qr/\.tar\..*/);
    return $filename;
}

################################################################################
################################################################################
### Tarball Names                                                            ###
################################################################################
################################################################################
my $LIBCOUCHBASE_TARBALL = lib_2_tarball('libcouchbase');

################################################################################
################################################################################
### Target Directory Structure                                               ###
################################################################################
################################################################################
my $TOPLEVEL = PLCB_ConfUtil::get_toplevel_dir();
my $INST_DIR = $BuildPrefix;
my $INCLUDE_PATH = File::Spec->catfile($INST_DIR, 'include');
my $LIB_PATH = File::Spec->catfile($INST_DIR, 'lib');

chdir $TOPLEVEL;

mkpath($INST_DIR);
mkpath($INCLUDE_PATH);
mkpath($LIB_PATH);

$ENV{PKG_CONFIG_PATH} .= ":"
. File::Spec->catfile($INST_DIR, 'lib', 'pkgconfig');

$ENV{LD_RUN_PATH} .= ":$RPATH";
$ENV{LD_LIBRARY_PATH} .= ":" . $ENV{LD_RUN_PATH};
$ENV{CPPFLAGS} .= $ENV_CPPFLAGS;
$ENV{LDFLAGS} .= $ENV_LDFLAGS;
$ENV{LIBS} .= $ENV_LIBS;

my $MAKEPROG = $ENV{MAKE};
if(!$MAKEPROG) {
    if(system("gmake --version") == 0) {
        $MAKEPROG = "gmake";
    } else {
        $MAKEPROG = "make";
    }
}


my $MAKE_CONCURRENT = $ENV{PLCB_MAKE_CONCURRENT};
$MAKEPROG = "$MAKEPROG $MAKE_CONCURRENT";

log_info("We're in $TOPLEVEL now");
my @COMMON_OPTIONS = (
"--prefix=$BuildPrefix",
qw(
--silent
--without-docs)
);

sub should_build {
    my $name = shift;
    $name = uc($name);
    exists $DEPS{$name};
}

sub lib_is_built {
    my $libname = shift;
    if(-e File::Spec->catfile($LIB_PATH, $libname . "." . $Config{so})) {
        return 1;
    }
    return 0;
}

################################################################################
### libcouchbase                                                             ###
################################################################################
#if (should_build('COUCHBASE')) {
{
    chdir $TOPLEVEL;
    chdir tarball_2_dir($LIBCOUCHBASE_TARBALL);

    my @libcouchbase_options = (
        @COMMON_OPTIONS,
    );

    if($^O =~ /solaris/) {
        print STDERR "Disabling tools (won't compile on solaris)\n";
        push @libcouchbase_options, '--disable-tools';
    }

    my $mockpath = File::Spec->catfile(
        __DIR__, 't', 'tmp', 'CouchbaseMock.jar');

    if(!-e $mockpath) {
        die("Can't find mock in $mockpath");
    }
    if($HAVE_JAVA && -e $mockpath) {
        push @libcouchbase_options, '--with-couchbasemock='.$mockpath;
    } else {
        push @libcouchbase_options, '--disable-couchbasemock';
    }

    runcmd("./configure", @libcouchbase_options) unless -e 'Makefile';
    runcmd("$MAKEPROG install");
    runcmd("$MAKEPROG check -s") if $RUN_TESTS;
}

exit(0);
