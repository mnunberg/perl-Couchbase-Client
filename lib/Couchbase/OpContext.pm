package Couchbase::OpContext;
use strict;
use warnings;
use Couchbase::Client::IDXConst;
use Data::Dumper;

our $AUTOLOAD;

sub AUTOLOAD {
    my $meth = (split(/::/, $AUTOLOAD))[-1];
    my $self = $_[0];
    my @args = @_;

    $args[0] = $self->_cbo; # CBO
    $args[3] = $self;
    @_ = @args;

    no strict 'refs';
    goto &{"Couchbase::Bucket::".$meth};
}


# Note, there is no new() method because this must be instantiated
# via XS directly.
1;
