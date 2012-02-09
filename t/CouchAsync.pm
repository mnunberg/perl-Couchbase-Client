package CouchAsync;
use strict;
use warnings;
use blib;
use Couchbase::Client::Async;
use Couchbase::Client::IDXConst;
use Couchbase::Client::Errors;

use POE;
use POE::Kernel;
use Data::Dumper;
use Log::Fu { level => "debug" };
use Devel::Peek;
use Array::Assign;

use base qw(POE::Sugar::Attributes);

my $poe_kernel = "POE::Kernel";
my $SESSION = 'couchbase-client-async';
my $OBJECT;
my %RequestStatus;


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
        },
        cb_waitdone => sub {
            log_warn("Wait is done..");
            POE::Kernel->yield("wait_done", @_);
        },
        cb_update_timer => sub {
            POE::Kernel->call($SESSION, "update_timer", @_);
        }
    });
    
    $OBJECT->connect();
}

sub unhandled :Event(_default) {
    log_errf("Got unknown event %s", $_[ARG0]);
}

sub got_error :Event {
    log_errf("Got errnum=%d, errstr=%s",
             $_[ARG0], $_[ARG1]);
}


my @OPERATIONS = (
    sub {
        my @params;
        arry_assign_i(@params,
            REQIDX_KEY, "async_key",
            REQIDX_VALUE, "async_value",
            REQIDX_EXP, 300);
        
        log_warn("Enqueuing SET request");
        $OBJECT->request(
            PLCBA_CMD_SET, REQTYPE_SINGLE,
            sub {
                my ($result,$ucookie) = @_;
                $result = delete $result->{$ucookie};
                log_warnf("(SET): Got result for %s: %s (%d)",
                          $ucookie, $result->is_ok
                          ? "SUCCESS" : $result->errstr,
                          $result->errnum);
            }, "async_key", CBTYPE_COMPLETION,
            \@params
        );
    },
    sub {
        my @params;
        arry_assign_i(@params,
            REQIDX_KEY, "async_key");
        log_warn("Enqueuing GET request");
        $OBJECT->request(
            PLCBA_CMD_GET, REQTYPE_SINGLE,
            sub {
                my ($result,$ucookie) = @_;
                $result = delete $result->{$ucookie};
                
                if($result->is_ok) {
                    log_warnf("(GET): Got result for %s: %s", $ucookie, $result->value);
                } else {
                    log_errf("Got error for %s: %s (%d)", $ucookie,
                             $result->errstr, $result->errnum);
                }
            }, "async_key", CBTYPE_COMPLETION,
            \@params
        );
    },
    #Try a set multi:
    sub {
        my @setlist;
        foreach my $k (qw(foo bar baz)) {
            my @params;
            arry_assign_i(@params,
                REQIDX_KEY, $k,
                REQIDX_VALUE, "ASYNC_VALUE_$k");
            push @setlist, \@params;
        }
        log_warn("Enqueuing SET(MULTI) request");
        $OBJECT->request(
            PLCBA_CMD_SET, REQTYPE_MULTI,
            sub {
                my ($hash,$ucookie) = @_;
                while (my ($key,$result) = each %$hash) {
                    log_warnf("SET MULTI: got result for %s: %s",
                              $key, $result->errstr || "OK");
                }
            }, "blah", CBTYPE_COMPLETION,
            \@setlist
        );
    }
);

use Carp qw(cluck);

sub wait_done :Event {
    #Suspend all event loops:
    log_debug("wait_done begin");
    if ((my $sub = shift @OPERATIONS)) {
        $sub->();
    }
}

#This would be an event-loop specific implementation of update_event
my %EVMETH_MAP = (
    COUCHBASE_WRITE_EVENT, "write",
    COUCHBASE_READ_EVENT, "read"
);

sub _activate_events {
    my ($cbc_flags, $dupfh, $opaque) = @_;
    while (my ($ev,$meth) = each %EVMETH_MAP ) {
        if($cbc_flags & $ev) {
            log_debugf("Activating event %d on dupfd %d", $ev, fileno($dupfh));
            $poe_kernel->${\"select_$meth"}($dupfh, "dispatch_event", $ev, $opaque);
        }
    }
}

sub _deactivate_events {
    my ($cbc_flags, $dupfh) = @_;
    while (my ($ev,$meth) = each %EVMETH_MAP ) {
        if($cbc_flags & $ev) {
            log_debugf("Deactivating event %d on dupfd %d", $ev, fileno($dupfh));
            $poe_kernel->${\"select_$meth"}($dupfh);
        }
    }
}

sub _startstop_events {
    my ($events,$prefix,$dupfh) = @_;
    while (my ($ev,$meth) = each %EVMETH_MAP) {
        if($events & $ev) {
            log_debugf("Invoking $prefix: $meth on dupfd %d", fileno($dupfh));
            $poe_kernel->${\"$prefix\_$meth"}($dupfh);
        }
    }
}


sub update_event :Event {
    my ($evdata,$action,$flags) = @_[ARG0..ARG2];
    my $dupfh = $evdata->[EVIDX_DUPFH];
    
    if($action == EVACTION_WATCH) {
        if(!$dupfh) {
            open $dupfh, ">&", $evdata->[EVIDX_FD];
            _activate_events($flags, $dupfh, $evdata->[EVIDX_OPAQUE]);
            $evdata->[EVIDX_DUPFH] = $dupfh;
        } else {
            my $events_do_delete = $evdata->[EVIDX_WATCHFLAGS] & (~$flags);
            log_debugf("Old events=%x, new events = %x, delete events %x",
                       $evdata->[EVIDX_WATCHFLAGS], $flags, $events_do_delete);
            _activate_events($flags, $dupfh, $evdata->[EVIDX_OPAQUE]);
            _deactivate_events($events_do_delete, $dupfh);
        }
    } elsif ($action == EVACTION_UNWATCH) {
        if(!$dupfh) {
            warn("Unwatch requested on undefined dup'd filehandle");
            return;
        }
        _deactivate_events($evdata->[EVIDX_WATCHFLAGS], $dupfh);
    } elsif ($action == EVACTION_SUSPEND || $action == EVACTION_RESUME) {
        if(!$dupfh) {
            warn("suspend/resume requested on undefined dup'd filehandle. ".
                 "fd=".$evdata->[EVIDX_FD]);
        }
        my $prefix = $action == EVACTION_SUSPEND ? "pause" : "resume";
        $prefix = "select_" . $prefix;
        _startstop_events($evdata->[EVIDX_WATCHFLAGS], $prefix, $dupfh);
    } else {
        die("Unhandled action $action");
    }
}

sub update_timer :Event {
    my ($evdata,$action,$usecs) = @_[ARG0..ARG2];
    my $timer_id = $evdata->[EVIDX_PLDATA];
    my $seconds;
    
    if($usecs) {
        $seconds = ($usecs / (1000*1000));
        log_err($usecs);
    }
    if($action == EVACTION_WATCH) {
        if(defined $timer_id) {
            log_debugf("Rescheduling timer %d in %0.5f seconds from now",
                       $timer_id, $seconds);
            $poe_kernel->delay_adjust($timer_id, $seconds)
        } else {
            $timer_id = $poe_kernel->delay_set(
                "dispatch_timeout", $seconds, $evdata->[EVIDX_OPAQUE]);
            $evdata->[EVIDX_PLDATA] = $timer_id;
            log_debugf("Scheduling timer %d for %0.5f seconds from now",
                       $timer_id, $seconds);
        }
    } else {
        if(defined $timer_id) {
            log_debug("Deletion requested for timer $timer_id.");
            $poe_kernel->alarm_remove($timer_id);
            $evdata->[EVIDX_PLDATA] = undef;
        } else {
            log_err("Requested to delete non-existent timer ID");
        }
    }
}

#this is what an event loop does in order to tell libcouchbase that an event
#has been received
sub dispatch_event :Event {
    my ($flags,$opaque) = @_[ARG2..ARG3];
    log_debugf("Flags=%d, opaque=%x", $flags, $opaque);
    Couchbase::Client::Async->HaveEvent($flags, $opaque);
}

sub dispatch_timeout :Event {
    my $opaque = $_[ARG0];
    my $flags = 0;
    log_debugf("Dispatching timer.. opaque=%x", $opaque);
    Couchbase::Client::Async->HaveEvent($flags, $opaque);
}

POE::Sugar::Attributes->wire_new_session($SESSION);

POE::Kernel->run();
