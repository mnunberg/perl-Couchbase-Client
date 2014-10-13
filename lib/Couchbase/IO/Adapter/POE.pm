package Couchbase::IO::Adapter::POE;
use strict;
use warnings;
use POE;
use POE::Kernel;
use POE::Session;
use Couchbase::IO::Constants;
use Carp qw(cluck);

my $poe_kernel = "POE::Kernel";

sub _dispatch_io {
    @_ = @_[ARG2..ARG3];
    goto &Couchbase::IO::Event::dispatch;
}

sub _dispatch_timer {
    @_ = ($_[ARG0],0);
    goto &Couchbase::IO::Event::dispatch;
}

my $is_poe_call;

sub update_event {
    my ($loopdata,$event,$flags,$sched_r,$sched_w,$stop_r,$stop_w) = @_[ARG0..ARG6];
    my $dupfh = $event->[COUCHBASE_EVIDX_DUPFH];
    if(!$dupfh) {
        open $dupfh, "+<&", $event->[COUCHBASE_EVIDX_FD];
        $event->[COUCHBASE_EVIDX_DUPFH] = $dupfh;
    }

    # Activate stuff
    $poe_kernel->select_read($dupfh, '_dispatch_io', $event, COUCHBASE_READ_EVENT) if $sched_r;
    $poe_kernel->select_write($dupfh, '_dispatch_io', $event, COUCHBASE_WRITE_EVENT) if $sched_w;

    # Stop stuff
    $poe_kernel->select_read($dupfh) if $stop_r;
    $poe_kernel->select_write($dupfh) if $stop_w;
}

sub update_timer {
    my ($loopdata,$event,$action,$seconds) = @_[ARG0..ARG3];
    my $timer_id = $event->[COUCHBASE_EVIDX_PLDATA];

    if($action == COUCHBASE_EVACTION_WATCH) {
        if(defined $timer_id) {
            $poe_kernel->delay_adjust($timer_id, $seconds)
        } else {
            $timer_id = $poe_kernel->delay_set('_dispatch_timer', $seconds, $event, 0);
            $event->[COUCHBASE_EVIDX_PLDATA] = $timer_id;
        }
    } else {
        if(defined $timer_id) {
            $poe_kernel->alarm_remove($timer_id);
            $event->[COUCHBASE_EVIDX_PLDATA] = undef;
        }
    }
}

sub do_call_direct {
    # Direct call, fill array properly:
    goto &update_event;
}

sub new_adapter {
    my $pkg = shift;

    my $obj = Couchbase::IO->new({
        event_update => sub {
            my $cur = $poe_kernel->get_active_session();
            if ($cur == $_[0]) {
                unshift(@_, undef) for (1..ARG0);
                goto &update_event;
            } else {
                $poe_kernel->call($_[0], 'update_event', @_);
            }
        },
        timer_update => sub {
            my $cur = $poe_kernel->get_active_session();
            if ($cur == $_[0]) {
                unshift(@_, undef) for (1..ARG0);
                goto &update_timer;
            } else {
                $poe_kernel->call($_[0], 'update_timer', @_)
            }
        }
    });

    my $session = POE::Session->create(
        inline_states => {
            update_timer => \&update_timer,
            update_event => \&update_event,
            _dispatch_timer => \&_dispatch_timer,
            _dispatch_io => \&_dispatch_io,
            _start => sub {}
        }
    );

    $obj->data($session);

    return $obj;
}

1;
