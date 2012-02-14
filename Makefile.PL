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



#We might want to figure out right now if we're linking against an existent
#libcouchbase, using a user-provided custom dynamic link, or dynamic link
my $myextlib;
my $inc;
my $libs;

my $buildscript_options = "";

if(!$UseDynamic) {
    my $inst_dir = PLCB_ConfUtil::get_inst_dir();
    $inc = '-I' . File::Spec->catfile($inst_dir, 'include');
    
    my $lib_dir = File::Spec->catfile($inst_dir, 'lib');
    
    $libs = "-L$lib_dir -lsasl2 -levent -ldl -lresolv";
    
    #Set path for linker and friends
    $myextlib = join(' ',
        map(File::Spec->catfile($lib_dir, $_.'$(LIB_EXT)'),
            qw(libcouchbase libvbucket)));
    
    {
        no warnings 'once';
        *MY::postamble = \&_static_my_postamble;
    }
} else {
    $myextlib = "";
    $libs = " -lcouchbase -lvbucket -lcouchbase_libevent";
}

foreach ([\$inc, \$ExtraInclude], [\$libs, \$ExtraLDPath]) {
    my ($defl,$extra) = @$_;
    if($$extra) {
        $$defl ||= "";
        $$defl = "$$extra $$defl";
    }
}

#Write our temporary parameters
PLCB_ConfUtil::write_tmpflags($inc, $libs);

# .c files
my @source_modules = qw(
    callbacks
    convert
    ctor
    async
    async_callbacks
    async_events
);

# .xs files
my @xs_modules = qw(
    Client
    Client_multi
);

my @objects = map {$_ . '.o' } (@source_modules, @xs_modules);

WriteMakefile(
    NAME                => 'Couchbase::Client',
    AUTHOR              => q{M. Nunberg <mnunberg@haskalah.org>},
    VERSION_FROM        => 'lib/Couchbase/Client.pm',
    ABSTRACT_FROM       => 'lib/Couchbase/Client.pm',
    OBJECT              => join(" ", @objects),

    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'perl')
      : ()),
      
    PL_FILES            => {
        #Force them to build into blib
        "error_constants.pl" => '$(INST_LIB)/Couchbase/Client/Errors_const.pm',
        "idx_constants.pl"  => '$(INST_LIB)/Couchbase/Client/IDXConst_const.pm'
    },
    
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
    'MYEXTLIB' => $myextlib,
    NEEDS_LINKING => 1,
    
    OPTIMIZE    => 
                ' -Wdeclaration-after-statement -Werror -std=gnu89 -fPIC',
                
    LIBS    => $libs,
    INC     => $inc,
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Couchbase-Client-* COMPILER_FLAGS' },
);

sub MY::libscan {
    my ($self,$path) = @_;
    if($path =~ /\.pl$/i) {
        return "";
    } else {
        return $path;
    }
}

sub _static_my_postamble {
    my $make_text = <<'EOM';
$(MYEXTLIB):
    $(PERLRUN) build_libraries.pl __BUILD_LIBRARIES_OPTIONS__
EOM

    $make_text =~ s/__BUILD_LIBRARIES_OPTIONS__/$buildscript_options/g;
    $make_text =~ s/^\s+/\t/msg;
    $make_text;
}