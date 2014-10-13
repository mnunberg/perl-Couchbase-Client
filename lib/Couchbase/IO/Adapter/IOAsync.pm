package Couchbase::IO::Adapter::IOAsync::Event;
use strict;
use warnings;
my $EVPACKAGE = __PACKAGE__;

use Couchbase::IO::Constants;
use base qw(Couchbase::IO::Event);
use Constant::Generate [qw(IX_LOOP)], start_at => COUCHBASE_EVIDX_MAX;

use Class::XSAccessor::Array {
    accessors => {
        ioh => COUCHBASE_EVIDX_PLDATA,
        loop => IX_LOOP
    }
};

package Couchbase::IO::Adapter::IOAsync;
use strict;
use warnings;

use Couchbase::IO::Constants;

use IO::Async;
use IO::Async::Loop;
use IO::Async::Timer::Countdown;

sub ioa_init_event {
    my ($data,$event) = @_;
    my $funcs = [
        sub {@_=($event);goto &Couchbase::IO::Event::dispatch_r}, # Read
        sub {@_=($event);goto &Couchbase::IO::Event::dispatch_w} # Write
    ];
    $event->data($funcs);
    bless $event, $EVPACKAGE;
}

sub ioa_update_event {
    my ($loop,$event,$flags,$sched_r,$sched_w,$remove_r,$remove_w) = @_;
    my $fh = $event->[COUCHBASE_EVIDX_DUPFH];
    my $funcs = $event->[COUCHBASE_EVIDX_PLDATA];
    my %params;

    (open($fh, "+<&", $event->fileno) or die "Couldn't dup") if !defined($fh);
    $event->[COUCHBASE_EVIDX_DUPFH] //= $fh;

    $params{on_read_ready} = $funcs->[0] if $sched_r;
    $params{on_write_ready} = $funcs->[1] if $sched_w;

    $params{handle} = $fh if ($sched_r||$sched_w||$remove_r||$remove_w);
    $loop->watch_io(%params) if ($sched_r || $sched_w);

    $params{on_read_ready} = $remove_r if $remove_r;
    $params{on_write_ready} = $remove_w if $remove_w;
    $loop->unwatch_io(%params) if ($remove_w || $remove_r);
}

sub ioa_init_timer {
    my ($data,$timer) = @_;
    bless $timer, $EVPACKAGE;

    my $iot = IO::Async::Timer::Countdown->new(
        on_expire => sub {
            @_ = ($timer);
            goto &Couchbase::IO::Event::dispatch_w;
        },
    );

    $timer->loop($data);
    $timer->ioh($iot);
    $timer->loop->add($iot);
}

sub ioa_update_timer {
    my ($data,$timer,$action,$newts) = @_;
    my $iot = $timer->data;

    if ($action == COUCHBASE_EVACTION_UNWATCH) {
        $iot->stop();
    } else {
        $iot->configure(delay => $newts);
        $iot->start();
    }
}

sub new_adapter {
    my ($pkg,$loop) = @_;
    Couchbase::IO->new({
        event_init => \&ioa_init_event,
        event_update => \&ioa_update_event,
        timer_init => \&ioa_init_timer,
        timer_update => \&ioa_update_timer,
        data => $loop
    });
}

1;
