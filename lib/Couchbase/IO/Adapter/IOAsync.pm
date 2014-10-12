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
    bless $event, $EVPACKAGE;
}

sub ioa_update_event {
    my ($data,$event,$action,$flags) = @_;
    my $ioh = $event->ioh;
    my $fh;
    my $remove_r = 0;
    my $remove_w = 0;

    if (! ($fh = $event->dupfh)) {
        open($fh, "+<&", $event->fileno) or die "Couldn't dup";
        $event->dupfh($fh);
    }

    my %params = (handle => $fh);

    if ($flags & COUCHBASE_READ_EVENT) {
        $params{on_read_ready} = sub {
            @_ = ($event);
            goto &Couchbase::IO::Event::dispatch_r;
        };
    } else {
        $remove_r = 1;
    }
    if ($flags & COUCHBASE_WRITE_EVENT) {
        $params{on_write_ready} = sub {
            @_ = ($event);
            goto &Couchbase::IO::Event::dispatch_w;
        }
    } else {
        $remove_w = 1;
    }

    if ($remove_r == 0 || $remove_w == 0) {
        $data->{Loop}->watch_io(%params);
    }
    if ($remove_r || $remove_w) {
        $params{on_write_ready} = $remove_w;
        $params{on_read_ready} = $remove_r;
        $data->{Loop}->unwatch_io(%params);
    }
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

    $timer->loop($data->{Loop});
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
        data => {
            Loop => $loop
        }
    });
}

1;
