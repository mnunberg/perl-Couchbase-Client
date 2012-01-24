package CouchAsync;
use strict;
use warnings;
use blib;
use Couchbase::Client::Async;
use Couchbase::Client::IDXConst;

use POE;
use POE::Kernel;
use Data::Dumper;
use Log::Fu;
use Devel::Peek;

use base qw(POE::Sugar::Attributes);

my $poe_kernel = "POE::Kernel";
my $SESSION = 'couchbase-client-async';
my $OBJECT;


sub cbc_connect :Start {
    $OBJECT = Couchbase::Client::Async->new({
        server => "127.0.0.1:8091",
        username => "Administrator",
        password => "123456",
        bucket => "membase0",
        cb_error => sub {
            POE::Kernel->post($SESSION, "got_error", @_);
        },
        cb_update_event => sub {
            POE::Kernel->call($SESSION, "update_event", @_);
        }
    });
    $OBJECT->connect();
}

sub got_error :Event {
    log_err("Got error:");
    print Dumper($_[ARG0]);
}

sub update_event :Event {
    my ($fdes,$flags,$opaque) = @_[ARG0..ARG2];
    my ($fd,$dupfh) = @$fdes;
    
    #Devel::Peek::Dump($opaque);
    
    if($flags == 0 && (!$dupfh)) {
        log_warn("Requested event deletion but we have no filehandle");
        return;
    }
    if($flags == 0) {
        $poe_kernel->select_read($dupfh);
        $poe_kernel->select_write($dupfh);
        return;
    }
    if(!$dupfh) {
        open $dupfh, ">&$fd" or die "Couldn't dup: $!";
        $fdes->[1] = $dupfh;
    }
    
    if($flags & COUCHBASE_READ_EVENT) {
        $poe_kernel->select_read(
            $dupfh, "dispatch_event", COUCHBASE_READ_EVENT, $opaque);                     
    } else {
        $poe_kernel->select_read($dupfh);
    }
    
    if($flags & COUCHBASE_WRITE_EVENT) {
        $poe_kernel->select_write(
            $dupfh, "dispatch_event", COUCHBASE_WRITE_EVENT, $opaque);
    } else {
        $poe_kernel->select_write($dupfh);
    }
    log_errf("Wired events=%d for fd=%d (dup=%d) arg=%x",
             $flags, $fd, fileno($dupfh), $opaque);
}

sub dispatch_event :Event {
    my ($flags,$opaque) = @_[ARG2..ARG3];
    log_errf("Flags=%d, opaque=%x", $flags, $opaque);
    Couchbase::Client::Async->HaveEvent($flags, $opaque);
}


POE::Sugar::Attributes->wire_new_session($SESSION);

POE::Kernel->run();