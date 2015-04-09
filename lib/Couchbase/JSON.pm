package Couchbase::JSON;
use strict;
use warnings;

my $jctor;

# This is an internal module which attempts to find the best module
# available. It will try `JSON::MaybeXS`, `JSON::XS`, and finally `JSON`.
eval {
    require JSON::MaybeXS;
    $jctor = sub { return JSON::MaybeXS->new(); };
};
if (!$jctor) {
    eval {
        require JSON::XS;
        $jctor = sub { return JSON::XS->new(); };
    };
    if ($@) {
        warn("Couldn't load an XS JSON module. JSON processing will be slow: $@");
    }
}
eval {
    require JSON;
    $jctor = sub { return JSON->new(); };
}; if ($@) {
    die("Couldn't find any valid JSON module: $@");
}

sub new {
    shift;
    return $jctor->(@_);
}

1;
