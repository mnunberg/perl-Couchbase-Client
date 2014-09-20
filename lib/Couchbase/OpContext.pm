package Couchbase::OpContext;
use strict;
use warnings;
use Data::Dumper;

our $AUTOLOAD;

sub AUTOLOAD {
    my $meth = (split(/::/, $AUTOLOAD))[-1];
    my $self = $_[0];
    my @args = @_;

    $args[0] = $self->[1]; # CBO
    $args[3] = $self;
    @_ = @args;

    no strict 'refs';
    goto &{"Couchbase::Bucket::".$meth};
}

sub wait_all {
    my $self = $_[0];
    my $cbo = $self->[1];
    eval {
        $cbo->_ctx_wait();
    };
    $cbo->_ctx_clear();

    if ($@) {
        die $@;
    }
}

# Note, there is no new() method because this must be instantiated
# via XS directly.
1;
