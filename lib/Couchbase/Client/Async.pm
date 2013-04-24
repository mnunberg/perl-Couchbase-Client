package Couchbase::Client::Async;
use strict;
use warnings;
our $VERSION = '2.0.0_1';
use Couchbase::Client;
use Couchbase::Client::IDXConst;
use Log::Fu;


sub new {
    my ($cls,$options) = @_;
    my @async_keys = qw(
        cb_update_event
        cb_error
        cb_waitdone
        cb_update_timer
        bless_events
    );
    my %async_opts;
    @async_opts{@async_keys} = delete @{$options}{@async_keys};

    my $arglist = Couchbase::Client::_MkCtorIDX($options);

    $arglist->[CTORIDX_CBEVMOD] = delete $async_opts{cb_update_event}
    and
    $arglist->[CTORIDX_CBERR] = delete $async_opts{cb_error}
    and
    $arglist->[CTORIDX_CBWAITDONE] = delete $async_opts{cb_waitdone}
    and
    $arglist->[CTORIDX_CBTIMERMOD] = delete $async_opts{cb_update_timer}

    or die "We require update_event, error, and wait_done callbacks";

    if($async_opts{bless_events}) {
        $arglist->[CTORIDX_BLESS_EVENT] = 1;
    }

    my $o = $cls->construct($arglist);
    return $o;
}

#Establish proxy methods:

foreach my $subname (qw(
    enable_compress
    compression_settings
    serialization_settings
    conversion_settings
    deconversion_settings
    compress_threshold
    timeout
)) {
    no strict 'refs';
    *{$subname} = sub {
        my ($self,@args) = @_;
        my $base = $self->_get_base_rv;

        @_ = ($base, @args);
        goto &{"Couchbase::Client::$subname"};
    };
}

1;

__END__

=head1 NAME

Couchbase::Client::Async - Asynchronous system for couchbase clients.

=head1 DESCRIPTION

This is a module intended for use by other higher level components which interact
directly with Perl event frameworks.

libcouchbase allows for pluggable event loops, which drive and tell it about
file descriptor events, timeouts, and other such nicetis.

The purpose of this module is to provide a unified library for perl, which will
be compatible with L<POE>,  L<AnyEvent>, L<IO::Async> and other event loops.

The module is divided into two components:

=head2 I/O Events

This part of the module provides an interface for event libraries to tell
libcouchbase about events, and conversely, have libcouchbase tell the event
library about new file descriptors and events.

=head2 Command Results and Events

This part of the module provides a framework in which event libraries can provide
interfaces to users, so that they can perform commands on a couchbase cluster, and
receive their results asynchronously.

=head1 EVENT MANAGEMENT

Event, Timer, and I/O management is the lower level of this module, and constitutes
the interface which event loop integrators would need to be most attune to.

At the most basic level, you are required to implement four callbacks. These
callbacks are indicated by values passed to their given hash keys in the object's
constructor.

=head3 C<cb_update_event>

    cb_update_event => sub {
        my ($evdata,$action,$flags) = @_;

        if(ref($evdata) ne "Couchbase::Client::Event") {
            bless $evdata, "Couchbase::Client::Event";
        }
        ...
    };

This callback is invoked to update and/or modify events. It receives three
arguments.

The first is C<$evdata> which is an array, which may be blessed into
L<Couchbase::Client::Async::Event>.

The C<$evdata> structure contains the state-'glue' for interaction with the
internal (C) event routines and their Perl dispatchers.

The following will mention some useful fields for the C<$evdata> structure. Note
this is not an exhaustive listing (see that class' documentation for that) but
a more practical guide as to what the fields are for, and how they may be used.

=over

=item C<fd>

This read-only field contains the numeric file descriptor on which the C library
will perform I/O functions. If your event loop supports watching file descriptor
numbers directly, you may simply watch this number; otherwise, look at the next
field

=item C<dupfh>

This mutatable field contains an optional dup'd Perl filehandle. Some Perl event
loops do not allow for watching a file descriptor directly and demand to be given
a 'PerlIO' filehandle (conforming to the L<IO::Handle> interface, or one of the
things returned by L<open>).

This filehandle should be a dup'd version of the C<fd> field, the reason being
that when the filehandle goes out of scope from perl, the underlying file
I<descriptor> will be C<close()>d. Since there is not necessarily a one-to-one
correlation between stream lifetimes as they exist in the Perl client, and their
lifetimes as they exist in libcouchbase, it is recommended that the file
descriptor be dup'd. In that way, close() on the dup'd file descriptor will not
affect the file descriptor in the C side.

The filehandle stored in the C<dupfh> field will remain active until the underlying
C<fd> is closed or changed.

The first time an event is created, the C<dupfh> field will be undef, and
the callback should check for this creation, and if true, create a new one,
using the following idiom:

    open my $dupfh, ">&", $evdata->fd;
    $evdata->dupfh($dupfh);

the C<dupfh> field will persist the next time the C<cb_update_event> callback
is invoked.

=item opaque

This contains opaque data to be passed to our L</HaveEvent> package method. You
must not modify this object in any way. Failure to comply will likely result in
a segfault.

=back

The third argument (we will get to the second argument later) is a bitfield of
flags, describing which events to watch for. Flags may be a bitwise-OR'd
combination of the following

=over

=item C<COUCHBASE_READ_EVENT>

Dispatch event when the stream will not block on read()

=item C<COUCHBASE_WRITE_EVENT>

Dispatch event when the stream will not block on write()

=back

Consequently, it is the responsibility of this callback to ensure that B<only>
the I/O events specified in C<$flags> are active, and that all others remain
inactive (spuriously delivering write events is a very bad idea).

To make life easier, the C<$evdata> structure has a C<old_flags> field which
contains the active events before this callback was invoked. Thus, instead of
explicitly disabling all non-listed events, one can do the following:

    my $events_to_delete = $evdata->old_flags & (~$flags);

and only handle the events mentioned in C<$events_to_delete>

The C<old_flags> will be set to the current value of C<$flags> once the callback
returns.


The second argument (C<$action>) specifies which type of update this is. It can
be one of the following:

=over

=item C<EVACTION_WATCH>

Request that the stream be watched for events

=item C<EVACTION_UNWATCH>

Remove all watchers on this stream, and possibly do cleanup

=item C<EVACTION_SUSPEND>

Temporarily disable the watching of events on this stream, but do not forget
about which events are active

=item C<EVACTION_RESUME>

Resume a suspended event

=back

The suspension and resumption of events may be necessary so that libcouchbase
only receives events when it is ready for them, without impacting performance by
re-selecting all file descriptors.

L<POE::Kernel> has C<select_resume_read> and C<select_pause_read>, for example.


For the C<EVACTION_WATCH> event, the implementation must have the event loop
dispatch to a function that will ultimately do something of the following:

    Couchbase::Client::Async->HaveEvent($which, $evdata->opaque);

Where the C<$which> argument contains the event which ocurred (either
C<COUCHBASE_READ_EVENT> or C<COUCHBASE_WRITE_EVENT>), and the C<opaque> argument
being the C<opaque> field passed in (this) callback.

See L</HaveEvent> for more details.

=head3 C<cb_update_timer>

    cb_update_timer => sub {
        my ($evdata,$action,$usecs) = @_;
        my $timer_id = $evdata->pl_data;

        if($action == EVACTION_WATCH) {
            if(defined $timer_id) {
                reschedule_timer($timer_id, $usecs / (1000*1000),
                    callback => 'Couchbase::Client::Async::HaveData',
                    args => ['Couchbase::Client::Async', 0, $evdata->opaque]);

            } else {
                $timer_id = schedule_timer(
                    $usecs / (1000*1000) ...
                );
            }
        } else {
            delete_timer($evdata->pl_data);
        }
    };

This callback is invoked to schedule an interval timer.
It is passed three arguments:

=over

=item C<$evdata>

The 'event'. See L</cb_update_event> for details.

=item C<$action>

This is one of C<EVACTION_WATCH> and C<EVACTION_UNWATCH>.

For C<EVACTION_WATCH>, a timer should be scheduled to trigger in the future, for
C<EVACTION_UNWATCH>, and active timer should be deleted.

=item C<$usecs>

How many microseconds from now should the timer be triggered.

=back

These timers should end up calling L</HaveEvent> when they expire. The first
argument to L</HaveEvent> (the flags) is ignored, but it must still be passed
the C<opaque> object from C<$evdata> (see L</cb_update_event> for details).

It is common for timers to require some kind of internal identifier by which
the event loop can allow their cancelling and postponing.

In order to maintain the timer, the C<$evdata> offers a Perl-only writeable
C<pl_data> field, which can hold anything you want it to.

Timers should not be affected (or ever receive) C<EVACTION_SUSPEND> or
C<EVACTION_RESUME> actions.

=head3 C<cb_waitdone>

This is called with no arguments whenever libcouchbase has determined it no longer
needs to watch any file descriptors. Normally the L</cb_update_timer> will be
called with C<EVACTION_SUSPEND> for all active file descriptor watchers.

This can be used to signal other layers that there are no more pending user events
to wait for.

=head3 C<cb_error>

This is called with two arguments, the first an internal libcouchbase error number,
and the second, a string describing the details of the error.


=head2 C<HaveEvent>

This is the 'return trip' function which should be called whenever an event is
ready. It is a package method and not an object method.

It is called as so:

    Couchbase::Client::Async->HaveEvent($flags, $opaque);

The C<$flags> argument is only relevant for I/O events (and not timers). The
C<$opaque> argument must be supplied and contains an internal pointer to a private
C data structure. RTFSC if you really wish to know what's inside there.

=head1 COUCHBASE COMMANDS AND RESULTS


=head2 command($type, $cmdargs, $cbparams)

Issue a command asynchronously.

The type is one of the C<PLCBA_CMD_*> constants:

=over

=item PLCBA_CMD_GET

=item PLCBA_CMD_TOUCH

=item PLCBA_CMD_LOCK

=item PLCBA_CMD_REPLACE

=item PLCBA_CMD_ADD

=item PLCBA_CMD_APPEND

=item PLCBA_CMD_PREPEND

=item PLCBA_CMD_SET

=item PLCBA_CMD_ARITHMETIC

=item PLCBA_CMD_INCR

=item PLCBA_CMD_DECR

=item PLCBA_CMD_REMOVE

=item PLCBA_CMD_UNLOCK

=back

The constants hopefully should be self-explanatory.

The second parameter, the C<$cmdargs>, is an array reference of arguments to
pass to the commands. These follow the same semantics as in the C<*_multi>
variants (in fact, internally they mostly follow the same code path).

Finally, the C<$cbparams> parameter is a hashref containing the following keys:

=over

=item C<callback>

Mandatory. A CODE reference or name of a function to be invoked when the
response arrives.

=item C<data>

Optional. A scalar which is passed to the callback as its second argument

=item C<type>

The type, or 'mode' of callback to use. Options are C<CBTYPE_INCREMENTAL>
and C<CBTYPE_COMPLETION>. The C<INCREMENTAL> type is useful if performing a
large get operation, where you wish to perform an action on each key as it arrives.

Otherwise, the default (C<CBTYPE_COMPLETION>) will only be invoked once the entire
set of commands have been completed.


=back

The callback is always invoked with two arguments; the first is a hashref
of keys and L<Couchbase::Client::Return> object values; the second is the
C<data> parameter (if passed).

A callback may thus look like this

    $async->command(PLCBA_CMD_GET, [ "key" ], {
        data => "hello there",
        callback => sub {
            my ($results, $data) = @_;
            my $single_result = $results->{key};
            $single_result->value;
            $single_result->is_ok; #etc..
            print "$data\n"; # hello there
    });


There are several convenience functions available as well:

=head2 get([$key], $cbparams)

=head2 get($key, $cbparams)

=head2 set($setparams, $cbparams)

=head2 add($addparams, $cbparams)

=head2 replace($replaceparams, $cbparams)

=head2 append($appendparams, $cbparams)

=head2 prepend($prependparams, $cbparams)

=head2 cas($casparams, $cbparams)

=head2 remove($rmparams, $cbparams)

=head2 get_multi(...)

=head2 set_multi(...)

=head2 add_multi(...)

=head2 replace_multi(...)

=head2 append_multi(...)

=head2 prepend_multi(...)

=head2 cas_multi(...)

=head2 remove_multi(...)
