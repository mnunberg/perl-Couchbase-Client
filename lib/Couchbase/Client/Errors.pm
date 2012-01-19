package Couchbase::Client::Errors;
use strict;
use warnings;
use base qw(Exporter);
require Couchbase::Client::Errors_const;
our @EXPORT;


if(!caller) {
    no strict 'refs';
    foreach my $const (@EXPORT) {
        my $val = &{$const}();
        printf("NAME: %s, VALUE=%d\n",
               $const, $val);
    }
}

1;