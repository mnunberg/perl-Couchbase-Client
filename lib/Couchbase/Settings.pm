package Couchbase::Settings;
use strict;
use warnings;

use Data::Dumper;

use Couchbase;
use Couchbase::_GlueConstants;

my %KEYMAP = (
    operation_timeout => [ 0x00, SETTING_TIMEOUT ],
    view_timeout => [ 0x01, SETTING_TIMEOUT ],
    error_thresh_count => [ 0x0C, SETTING_SIZE ],
    durability_timeout => [ 0x0D, SETTING_TIMEOUT ],
    durability_interval => [ 0x0E, SETTING_TIMEOUT ],
    http_timeout => [ 0x0F, SETTING_TIMEOUT ],
    config_total_timeout => [ 0x12, SETTING_TIMEOUT ],
    config_node_timeout => [ 0x1B, SETTING_TIMEOUT ],
    # Read only
    certpath => [ 0x22, SETTING_STRING ]
    ## ...
);

sub TIEHASH {
    my ($clsname, $cbo) = @_;
    return bless { _cbo => $cbo }, $clsname;
}

sub STORE {
    my ($self, $key, $value) = @_;
    my $spec = $KEYMAP{$key};
    if (!$spec) {
        warn("Unknown key $key");
        return;
    }
    $self->{_cbo}->_cntl_set($spec->[0], $spec->[1], $value);
}

sub FETCH {
    my ($self, $key) = @_;
    my $spec = $KEYMAP{$key};
    if (!$spec) {
        warn("Unknown key $key");
        return;
    }
    return $self->{_cbo}->_cntl_get($spec->[0], $spec->[1]);
}

sub EXISTS {
    my ($self, $key) = @_;
    return exists $KEYMAP{$key};
}

sub FIRSTKEY {
    my $self = shift;
    $self->{_iterctx} = { %KEYMAP };
    each %{$self->{_iterctx}};
}

sub NEXTKEY {
    my $self = shift;
    return each %{$self->{_iterctx}};
}

1;
