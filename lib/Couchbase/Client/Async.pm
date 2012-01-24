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
    );
    my %async_opts;
    @async_opts{@async_keys} = delete @{$options}{@async_keys};
    
    my $arglist = Couchbase::Client::_MkCtorIDX($options);
    
    $arglist->[CTORIDX_CBEVMOD] = delete $async_opts{cb_update_event}
    and
    $arglist->[CTORIDX_CBERR] = delete $async_opts{cb_error}
    or die "We require both update_event and error callbacks";
    
    
    my $o = $cls->construct($arglist);
    return $o;
}

1;