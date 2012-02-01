use strict;
use warnings;
use ExtUtils::MakeMaker;
use Dir::Self;

use lib __DIR__;

my $plcb_config = do 'PLCB_Config.pm';

my $include_path = $plcb_config->{COUCHBASE_INCLUDE_PATH} || "";
my $library_path = $plcb_config->{COUCHBASE_LIBRARY_PATH} || "";

if($include_path) {
    $include_path = "-I$include_path";
}
if($library_path) {
    $library_path = "-L$library_path";
}

WriteMakefile(
    NAME                => 'Couchbase::Client',
    AUTHOR              => q{M. Nunberg <mnunberg@haskalah.org>},
    VERSION_FROM        => 'lib/Couchbase/Client.pm',
    ABSTRACT_FROM       => 'lib/Couchbase/Client.pm',
    OBJECT              => 'callbacks.o convert.o ctor.o Client.o ' .
                            'async.o async_callbacks.o async_events.o ' .
                            'Client_multi.o',

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
    OPTIMIZE    => '-O0 -ggdb3',
    LIBS    => ["$library_path -lcouchbase -lcouchbase_libevent"],
    INC     => $include_path,
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Couchbase-Client-*' },
);
