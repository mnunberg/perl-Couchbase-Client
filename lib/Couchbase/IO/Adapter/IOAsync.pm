package Couchbase::IO::Adapter::IOAsync::Event;
use strict;
use warnings;
my $EVPACKAGE = __PACKAGE__;

use Couchbase::IO::Constants;
use base qw(Couchbase::IO::Event);
use Constant::Generate [qw(IX_LOOP IX_ADDED)], start_at => COUCHBASE_EVIDX_MAX;

use Class::XSAccessor::Array {
    accessors => {
        ioh => COUCHBASE_EVIDX_PLDATA,
        added => IX_ADDED,
        loop => IX_LOOP
    }
};

sub dispatch {
    my ($self,$flags) = @_;
    $self->loop->remove($self->ioh);
    $self->added(0);
    goto &Couchbase::IO::Event::dispatch;
}

sub suspend {
    my $self = $_[0];
    if ($self->added) {
        $self->loop->remove($self->ioh);
        $self->added(0);
    }
}

sub ensure_added {
    my $self = $_[0];
    if (!$self->added) {
        $self->loop->add($self->ioh);
        $self->added(1);
    }

}


package Couchbase::IO::Adapter::IOAsync;
use strict;
use warnings;

use Couchbase::IO::Constants;

use IO::Async;
use IO::Async::Loop;
use IO::Async::Handle;
use IO::Async::Timer::Countdown;

sub ioa_init_event {
    my ($data,$event) = @_;
    bless $event, $EVPACKAGE;

    my $ioh = IO::Async::Handle->new(
        on_read_ready => sub { $event->dispatch(COUCHBASE_READ_EVENT) },
        on_write_ready => sub { $event->dispatch(COUCHBASE_WRITE_EVENT) }
    );

    $event->ioh($ioh);
    $event->loop($data->{Loop});
}

sub ioa_update_event {
    my ($data,$event,$action,$flags) = @_;
    my $ioh = $event->ioh;

    if (!$event->dupfh) {
        open(my $fh, "+<&", $event->fileno) or die "Couldn't dup";
        $event->dupfh($fh);
        $ioh->set_handle($event->dupfh);
    }

    if ($action == COUCHBASE_EVACTION_UNWATCH) {
        $event->suspend();
        return;
    }

    $ioh->want_readready($flags & COUCHBASE_READ_EVENT);
    $ioh->want_writeready($flags & COUCHBASE_WRITE_EVENT);
    $event->ensure_added();
}

sub ioa_init_timer {
    my ($data,$timer) = @_;
    bless $timer, $EVPACKAGE;
    my $iot = IO::Async::Timer::Countdown->new(
        on_expire => sub { $timer->dispatch(0) },
    );
    $timer->loop($data->{Loop});
    $timer->ioh($iot);
}

sub ioa_update_timer {
    my ($data,$timer,$action,$newts) = @_;
    my $iot = $timer->data;
    my $loop = $data->{Loop};

    if ($action == COUCHBASE_EVACTION_UNWATCH) {
        $timer->suspend();
    } else {
        $iot->configure(delay => $newts);
        $iot->start();
        $timer->ensure_added();
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
