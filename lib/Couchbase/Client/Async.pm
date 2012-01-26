package Couchbase::Client::Async;
use strict;
use warnings;
our $VERSION = '0.01_1';
require XSLoader;
XSLoader::load('Couchbase::Client', $VERSION);
use Couchbase::Client;
use Couchbase::Client::IDXConst;
use Log::Fu;


sub new {
    my ($cls,$options) = @_;
    my @async_keys = qw(
        cb_update_event
        cb_error
        cb_waitdone
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
    
    or die "We require update_event, error, and wait_done callbacks";
    
    if($async_opts{bless_events}) {
        $arglist->[CTORIDX_BLESS_EVENT] = 1;
    }
    
    my $o = $cls->construct($arglist);
    return $o;
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

