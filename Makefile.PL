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
    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'perl')
      : ()),
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
    },
    NEEDS_LINKING => 1,
    LIBS    => ['-L/sources/libcouchbase/.libs -lcouchbase'],
    INC     => '-I/sources/libcouchbase/include /sources/memcached/include',
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Couchbase-Client-*' },
);
