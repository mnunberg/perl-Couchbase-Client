#!/usr/bin/perl
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

GetOptions(
    'dynamic' => \my $UseDynamic,
    'include=s' => \my $ExtraInclude,
    'ldpath=s' => \my $ExtraLDPath,
);

my %MM_Options;
################################################################################
### Our C Source Files                                                       ###
################################################################################
{
    my @C_Modules = qw(
        callbacks convert ctor async_base async_callbacks async_events);
    my @XS_Modules = qw(Client Client_multi);
    
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
foreach ([qw(error Errors)], [qw(idx IDXConst)]) {
    my ($script,$genpm) = @$_;
    $script = "constants/$script" . "_constants.pl";
    $genpm = '$(INST_LIB)/Couchbase/Client/' . "$genpm" . "_const.pm";
    $MM_Options{PL_FILES}->{$script} = $genpm;
}

################################################################################
### Check dependencies                                                       ###
################################################################################
my $inc;
my $libs;

################################################################################
### Check build type and options                                             ###
################################################################################
my $myextlib;

my $inst_dir = PLCB_ConfUtil::get_inst_dir();
my $inst_lib_dir = File::Spec->catfile($inst_dir, 'lib');
my $inst_inc_dir = File::Spec->catfile($inst_dir, 'include');

my $buildscript_options = "";

#my @extra_deps;
#foreach my $dep (['sasl2', 'sasl'], ['event', 'event']) {
#    my ($installed,$new) = @$dep;
#    print STDERR "Checking if $installed is present...";
#    if(check_lib(lib => $installed,
#                 LIBS => $ExtraLDPath, INC => $ExtraInclude)) {
#        print STDERR "OK\n";
#        push @extra_deps, "-l$installed";
#    } else {
#        print STDERR "NOT FOUND (will build embedded)\n";
#        push @extra_deps, File::Spec->catfile($inst_lib_dir,
#                                              "lib".$new.$Config{lib_ext});
#        $buildscript_options .= ' --build-'.$new;
#    }
#}

if(!$UseDynamic) {
    $inc = '-I' . $inst_inc_dir;
    $libs = "-L$inst_lib_dir -lsasl2 -levent -ldl -lresolv";
    
    #Set path for linker and friends
    $myextlib = join(' ',
        map(File::Spec->catfile($inst_lib_dir, $_.'$(LIB_EXT)'),
            qw(libcouchbase libvbucket)));
} else {
    $myextlib = "";
    $libs = " -lcouchbase -lvbucket -lcouchbase_libevent";
}

{
    $inc .= " " . join(" ", map("-I$_", split(/\s+/, $Config{locincpth})));
    $libs .= " " . join(" ", map("-L$_", split(/\s+/, $Config{libpth})));
}

foreach ([\$inc, \$ExtraInclude], [\$libs, \$ExtraLDPath]) {
    my ($defl,$extra) = @$_;
    if($$extra) {
        $$defl ||= "";
        $$defl = "$$extra $$defl";
    }
}

$MM_Options{INC} = $inc;
$MM_Options{LIBS} = $libs;
$MM_Options{MYEXTLIB} = $myextlib;

#Write our temporary parameters
PLCB_ConfUtil::write_tmpflags($inc, $libs);



WriteMakefile(
    NAME                => 'Couchbase::Client',
    AUTHOR              => q{M. Nunberg <mnunberg@haskalah.org>},
    VERSION_FROM        => 'lib/Couchbase/Client.pm',
    ABSTRACT_FROM       => 'lib/Couchbase/Client.pm',
    
    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'perl')
      : ()),      
    
    CONFIGURE_REQUIRES => {
        'Dir::Self' => 0,
    },

    PREREQ_PM => {
        'Array::Assign'     => 0,
        'ExtUtils::H2PM'    => 0.08,
        'Class::XSAccessor' => 1.11,
        'Test::More'        => 0,
        
        #We need libevent for whatever we're doing
        'Alien::Libevent'   => 0.001004,
        
        #These modules are needed for tests, but not strictly required for
        #functionality
        
        'Log::Fu'           => 0.25,
        'Test::Class'       => 0.36,
        
        #these are needed for asynchronous tests and modules
        'POE::Sugar::Attributes' => 0.02,
        'POE'               => 1.312,
    },

    NEEDS_LINKING => 1,    
    OPTIMIZE    => 
                ' -Wdeclaration-after-statement -Werror -std=gnu89',
                
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Couchbase-Client-* COMPILER_FLAGS' },
    %MM_Options,
);


package MY;
use Config;
use strict;
use warnings;

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
    if($path =~ /\.pl$/i) {
        return "";
    } else {
        return $path;
    }
}

sub postamble {
    return unless $myextlib;
    
    my $make_text = <<'EOM';
$(MYEXTLIB):
    $(PERLRUN) build_libraries.pl __BUILD_LIBRARIES_OPTIONS__
EOM

    $make_text =~ s/__BUILD_LIBRARIES_OPTIONS__/$buildscript_options/g;
    $make_text =~ s/^\s+/\t/msg;
    $make_text;
}