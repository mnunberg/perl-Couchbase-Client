package Couchbase::Bucket::KV;
use strict;
use warnings;
use base qw(Couchbase::Bucket);

sub upsert {
    my ($self, $key, $value) = @_;
    return $self->SUPPER::upsert($key, $value);
}
