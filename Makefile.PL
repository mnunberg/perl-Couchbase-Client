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

if(!$UseDynamic) {
    my $inst_dir = File::Spec->catfile('src', 'inst');
    my $lib_dir = File::Spec->catfile($inst_dir, 'lib');
    
    #Set path for linker and friends
    $myextlib = join(' ',
        map(File::Spec->catfile($lib_dir, $_.'$(LIB_EXT)'),
            qw(libcouchbase libvbucket)));
    
    #set include path
    $inc = '-I' . File::Spec->catfile($inst_dir, 'include');
    $libs = '-lsasl2 -levent -ldl -lresolv';
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
        $$defl = "$$extra $$defl";
    }
}

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
        "error_constants.pl" => "lib/Couchbase/Client/Errors_const.pm",
        "idx_constants.pl"  => "lib/Couchbase/Client/IDXConst_const.pm"
    },
    
    CONFIGURE_REQUIRES => {
        'Dir::Self' => 0,
    },

    PREREQ_PM => {
        'Array::Assign'     => 0,
        'ExtUtils::H2PM'    => 0.08,
        'Class::XSAccessor' => 1.11,
        'Test::More'        => 0,
        
        #These modules are needed for tests, but not strictly required for
        #functionality
        
        'Log::Fu'           => 0.25,
        'Test::Class'       => 0.36,
        'LWP::UserAgent'    => 0,
        
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
    clean               => { FILES => 'Couchbase-Client-*' },
);


sub _static_my_postamble {
    my $make_text = <<'EOM';
$(MYEXTLIB):
    $(PERLRUN) build_libraries.pl
EOM

    $make_text =~ s/^\s+/\t/msg;
    $make_text;
}