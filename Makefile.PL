use strict;
use warnings;
use ExtUtils::MakeMaker;

system("$^X error_constants.pl lib/Couchbase/Client/Errors_const.pm");
system("$^X idx_constants.pl lib/Couchbase/Client/IDXConst_const.pm");

WriteMakefile(
    NAME                => 'Couchbase::Client',
    AUTHOR              => q{M. Nunberg <mnunberg@haskalah.org>},
    VERSION_FROM        => 'lib/Couchbase/Client.pm',
    ABSTRACT_FROM       => 'lib/Couchbase/Client.pm',
    OBJECT              => 'callbacks.o convert.o ctor.o Client.o ' .
                            'async.o async_callbacks.o',

    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'perl')
      : ()),
    PL_FILES            => {},
    PREREQ_PM => {
        'Array::Assign'     => 0,
        'ExtUtils::H2PM'    => 0.08,
        'Class::XSAccessor' => 1.11,
        'Test::More'        => 0,
    },
    NEEDS_LINKING => 1,
    OPTIMIZE    => '-O0 -ggdb3',
    LIBS    => ['-L/sources/libcouchbase/.libs -lcouchbase -lcouchbase_libevent'],
    #LIBS     => ['-lcouchbase'],
    INC     => '-I/sources/libcouchbase/include /sources/memcached/include',
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Couchbase-Client-*' },
);
