package Couchbase::Test::Async::Loop;
use strict;
use warnings;
use Couchbase::Client::Async;
use Couchbase::Client::IDXConst;
use Couchbase::Client::Errors;

use POE;
use POE::Kernel;
use POE::Session;
use Data::Dumper;
use Log::Fu { level => "info" };
use Devel::Peek;
use Array::Assign;

use base qw(POE::Sugar::Attributes);

my $poe_kernel = "POE::Kernel";

sub cbc_connect :Start {
    $_[HEAP]->object->connect();
}

sub unhandled :Event(_default) {
    log_errf("Got unknown event %s", $_[ARG0]);
}

sub got_error :Event {
    log_errf("Got errnum=%d, errstr=%s",
             $_[ARG0], $_[ARG1]);
    $_[HEAP]->on_error(@_[ARG0,ARG1]);
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
            log_debug("Requested to delete non-existent timer ID");
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


#### External interface

use Class::XSAccessor {
    constructor => 'new',
    accessors => [qw(object alias on_ready on_error)]
};

sub spawn {
    my ($cls,$session_name,%options) = @_;
    my $cb_ready = delete $options{on_ready}
        or die ("Must have on_ready callback");
    my $user_error_callback = delete $options{on_error};

    my $async = Couchbase::Client::Async->new({
        %options,
        cb_error =>
            sub { $poe_kernel->post($session_name, "got_error", @_) },
        cb_update_event =>
            sub { $poe_kernel->call($session_name, "update_event", @_) },

        cb_waitdone => $cb_ready,

        cb_update_timer =>
            sub { $poe_kernel->call($session_name, "update_timer", @_) }
    });

    my $o = __PACKAGE__->new(alias => $session_name, object => $async,
                             on_error => $user_error_callback);
    POE::Session->create(
        heap => $o,
        inline_states =>
            POE::Sugar::Attributes->inline_states(__PACKAGE__, $session_name)
    );
    $async->connect();
    return $o;
}

sub _single_dispatch_common {
    my ($result,$arg) = @_;
    my ($key) = keys %$result;
    my ($ret) = values %$result;

    if($arg->{callback}) {
        $arg->{callback}->($key, $ret, $arg->{arg});
    } else {
        $poe_kernel->post($arg->{session}, $arg->{state},
                          $key, $ret,$arg->{arg});
    }
}

my %STR2CMD = (
    set => PLCBA_CMD_SET,
    cas => PLCBA_CMD_CAS,
    add => PLCBA_CMD_ADD,
    replace => PLCBA_CMD_REPLACE,
    append => PLCBA_CMD_APPEND,
    prepend => PLCBA_CMD_PREPEND,
    get => PLCBA_CMD_GET,
    lock => PLCBA_CMD_LOCK,
    touch => PLCBA_CMD_TOUCH,
    remove => PLCBA_CMD_REMOVE,
    arithmetic => PLCBA_CMD_ARITHMETIC,
    incr => PLCBA_CMD_INCR,
    decr => PLCBA_CMD_DECR
);

sub _catchall :Event(set, get, cas, add, replace, remove, arithmetic, incr, decr, replace, append, prepend)
{
    my ($op_params, $cb_params) = @_[ARG0, ARG1];
    if (!exists $STR2CMD{$_[STATE]}) {
        die("Unknown command: ".$_[STATE]);
    }

    if( $cb_params->{state} && (!$cb_params->{session}) ) {
        $cb_params->{session} = $_[SENDER];
    }

    unless($cb_params->{state} || $cb_params->{callback}) {
        die("Must have either target state or CODE reference for notification");
    }

    if($cb_params->{callback}) {
        unless(ref $cb_params->{callback} eq 'CODE') {
            die("Callback must be a CODE reference");
        }
    }

    my $cmdi = $STR2CMD{$_[STATE]};
    $_[HEAP]->object->command(
        $cmdi,
        $op_params,
        {
            callback => \&_single_dispatch_common,
            data => $cb_params,
            type => CBTYPE_COMPLETION
        }
    );
}

1;
