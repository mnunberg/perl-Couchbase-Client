package Couchbase::Client;
require XSLoader;
use strict;
use warnings;

use Couchbase::Client::Errors;
use Couchbase::Client::IDXConst;

use Log::Fu;
use Array::Assign;

our $VERSION = '0.01_1';
XSLoader::load(__PACKAGE__, $VERSION);

sub v_debug {
    my ($self,$key) = @_;
    my $ret = $self->get($key);
    my $value = $ret->[RETIDX_VALUE];
    if(defined $value) {
        log_infof("Got %s=%s OK", $key, $value);
    } else {
        log_errf("Got error for %s: %s (%d)", $key,
                 $ret->[RETIDX_ERRSTR], $ret->[RETIDX_ERRNUM]);
    }
}

sub k_debug {
    my ($self,$key,$value) = @_;
    my $status = $self->set($key, $value);
    if($status->[RETIDX_ERRNUM] == COUCHBASE_SUCCESS) {
        log_infof("Setting %s=%s OK", $key, $value);
    } else {
        log_errf("Setting %s=%s ERR: %s (%d)",
                 $key, $value,
                 $status->[RETIDX_ERRSTR], $status->[RETIDX_ERRNUM]);
    }
}
sub new {
    my ($pkg,$opts) = @_;
    my $server;
    my @arglist;
    my $servers = $opts->{servers};
    if(!$servers) {
        $server = $opts->{server};
    } else {
        $server = $servers->[0];
    }
    
    if(!$server) {
        die("Must have server");
    }
    arry_assign_i(@arglist,
        CTORIDX_SERVERS, $server,
        CTORIDX_USERNAME, $opts->{username},
        CTORIDX_PASSWORD, $opts->{password},
        CTORIDX_BUCKET, $opts->{bucket});
    my $o = $pkg->construct(\@arglist);
    return $o;
}

if(!caller) {
    my $o = __PACKAGE__->new({
        server => '10.0.0.99:8091',
        username => 'Administrator',
        password => '123456',
        bucket => 'membase0'
    });
    $o->k_debug("Foo", "FooValue");
    $o->k_debug("Bar", "BarValue");
    $o->v_debug("Foo");
    $o->v_debug("Bar");
    
}

1;