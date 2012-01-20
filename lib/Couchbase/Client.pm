package Couchbase::Client;
require XSLoader;
use strict;
use warnings;

use Couchbase::Client::Errors;
use Couchbase::Client::IDXConst;

use Log::Fu { level => "debug" };
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
        my $errors = $self->get_errors;
        foreach my $errinfo (@$errors) {
            my ($errnum,$errstr) = @$errinfo;
            log_errf("%s (%d)", $errstr,$errnum);
        }
    }
}

sub k_debug {
    my ($self,$key,$value) = @_;
    #log_debug("k=$key,v=$value");
    my $status = $self->set($key, $value);
    if($status->[RETIDX_ERRNUM] == COUCHBASE_SUCCESS) {
        log_infof("Setting %s=%s OK", $key, $value);
    } else {
        my $errors = $self->get_errors;
        foreach my $errinfo (@$errors) {
            my ($errnum,$errstr) = @$errinfo;
            log_errf("%s (%d)", $errstr,$errnum);
        }

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
    my $errors = $o->get_errors;
    foreach (@$errors) {
        my ($errno,$errstr) = @$_;
        log_err($errstr);
    }
    return $o;
}

if(!caller) {
    my $o = __PACKAGE__->new({
        server => '10.0.0.99:8091',
        username => 'Administrator',
        password => '123456',
        #bucket  => 'nonexist',
        bucket => 'membase0'
    });
    my @klist = qw(Foo Bar Baz Blargh Bleh Meh Grr Gah);
    $o->k_debug($_, $_."Value") for @klist;
    $o->v_debug($_) for @klist;
    $o->v_debug("NonExistent");
    $o->set("foo", "bar", 100);   
}

1;
