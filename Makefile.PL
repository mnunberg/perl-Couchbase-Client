#!/usr/bin/perl
package PLCBTopLevel;
use strict;
use warnings;
use ExtUtils::MakeMaker;
use Dir::Self;
use Getopt::Long;
use Config;
use File::Spec;
use Config;
use lib __DIR__;
use PLCB_ConfUtil;
use lib 'inc';
use Devel::CheckLib;
use Data::Dumper;

$ENV{LD_RUN_PATH} ||= "";

#$Verbose = 99;

GetOptions(
    'dynamic' => \my $UseDynamic,
    'bundled' => \my $UseBundled,
    'incpath=s' => \our $U_IncPath,
    'libpath=s' => \our $U_LibPath
) or die <<EOD;
OPTIONS:
--incpath=CPPFLAGS
--libpath=LDFLAGS
EOD

#my $mm = ExtUtils::MakeMaker->new();

our (@LIBS,$INC);
our $MM_TopLevel;
our $Constants_INC = "";
our $HaveJava = 0;

push @LIBS, $U_LibPath if $U_LibPath;
$INC = $U_IncPath || "";
$Constants_INC = $INC;


push @LIBS, '-lcouchbase';

my %MM_Options = (
    INC => $INC,
    LIBS => [ join(' ', @LIBS) || '' ],
);

$MM_Options{CONFIGURE} = sub {
    my ($cls,$h) = @_;
    $MM_TopLevel = $h;
    return $h;
};

################################################################################
### Our C Source Files                                                       ###
################################################################################
{
    my @C_Modules = qw(
        args
        callbacks
        convert
        operations
        viewhandle);
    my @XS_Modules = qw(
        Couchbase View BucketConfig);

    foreach (@XS_Modules, @C_Modules) {
        my $obj = $_ . $Config{obj_ext};
        push @{ $MM_Options{OBJECT} }, File::Spec->catfile('xs', $obj);
    }

    $MM_Options{OBJECT} = join(' ', @{$MM_Options{OBJECT}});

    foreach my $xs (@XS_Modules) {
        $xs = File::Spec->catfile('xs', $xs);
        my $c = "$xs.c";
        $xs = "$xs.xs";
        $MM_Options{XS}->{$xs} = $c;
    }
}

################################################################################
### These scripts generate constants                                         ###
################################################################################
foreach ([qw(error Constants)], [qw(idx _GlueConstants)]) {
    my ($script,$genpm) = @$_;
    $script = "constants/$script" . "_constants.pl";
    $genpm = '$(INST_LIB)/Couchbase/' . "$genpm" . "_const.pm";
    $MM_Options{PL_FILES}->{$script} = $genpm;
}

################################################################################
### Check build type and options                                             ###
################################################################################

if($ENV{PLCB_BUILD_AUTHOR}) {
    $MM_Options{OPTIMIZE} = '-Wdeclaration-after-statement -Werror -std=gnu89';
}

# Extra stuff - add compiler flags here
# $MM_Options{OPTIMIZE} .= ' -Wall';

################################################################################
### Check for Java                                                           ###
################################################################################
print STDERR "Checking for working Java (for tests)\n. Running java -version\n";
$HaveJava = (system("java -version") == 0);
if(!$HaveJava) {
    my $promptval = prompt(
        "java was not found in your path. You must have java to properly\n".
        "test Couchbase::Client. Java is not a runtime dependency and this\n".
        "module will likely function properly without it, but will be untested\n".
        "on your specific installation.\n\n".
        "Abort installation?", "n");

    if($promptval =~ /^y/i) {
        print STDERR "You have request to abort the installation.\n".
                        "Makefile.PL will now exit\n";
        exit(0);
    }
}

use Log::Fu;

$MM_Options{NEEDS_LINKING} = 1;

$MM_Options{META_MERGE} = {
    resources => {
        repository => 'https://github.com/mnunberg/perl-Couchbase-Client'
    }
};

WriteMakefile(
    NAME                => 'Couchbase',
    AUTHOR              => q{M. Nunberg <mnunberg@haskalah.org>},
    VERSION_FROM        => 'lib/Couchbase.pm',
    ABSTRACT_FROM       => 'lib/Couchbase.pm',

    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'perl')
      : ()),

    CONFIGURE_REQUIRES => {
        'Dir::Self' => 0,
        'Log::Fu'           => 0.25,
    },

    BUILD_REQUIRES => {
        'ExtUtils::H2PM'    => 0.08,

        #This is really a dependency of ExtUtils::H2PM, but we need a
        #version which honors the CFLAGS environment variable.
        'ExtUtils::CBuilder' => 0.280203,

        #Need this to extract tarballs
        'Archive::Extract' => 0,
        'Archive::Tar' => 0,
    },

    PREREQ_PM => {
        'Class::XSAccessor' => 1.11,

        'JSON'              => 2.53,
        'JSON::SL'          => '1.0.1'
    },

    TEST_REQUIRES => {
        #These modules are needed for tests, but not strictly required for
        #functionality

        'Test::More'        => 0,
        'Test::Class'       => 0.36
    },

    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Couchbase-* COMPILER_FLAGS log.test-*' },
    %MM_Options,
);


#Write a list of compiler flags for our constants scripts.
PLCB_ConfUtil::write_tmpflags($Constants_INC);

package MY;
use Config;
use strict;
use warnings;
use Data::Dumper;

#thanks rafl!
sub const_cccmd {
    my $ret = shift->SUPER::const_cccmd(@_);
    return q{} unless $ret;
    if ($Config{cc} =~ /^cl\b/i) {
        warn 'you are using MSVC... my condolences.';
        $ret .= ' /Fo$@';
    } else {
        $ret .= ' -o $@';
    }
    return $ret;
}

sub libscan {
    my ($self,$path) = @_;
    if($path =~ /\.pl$/i || $path =~ /PLCB_Conf/ || $path =~ /HACKING/) {
        return "";
    } else {
        return $path;
    }
}
