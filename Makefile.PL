#!/usr/bin/perl
use strict;
use warnings;
use ExtUtils::MakeMaker;
use Dir::Self;

use lib __DIR__;
use PLCB_ConfUtil;

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
    NEEDS_LINKING => 1,
    OPTIMIZE    => '-O0 -ggdb3 -Wdeclaration-after-statement -Werror -std=gnu89',
    #CCFLAGS  => '-Wdeclaration-after-statement',
    LIBS    => [PLCB_ConfUtil::get_gcc_linker_flags],
    INC     => PLCB_ConfUtil::get_include_dir,
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Couchbase-Client-*' },
);
