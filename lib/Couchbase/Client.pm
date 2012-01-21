package Couchbase::Client;
require XSLoader;
use strict;
use warnings;

use Couchbase::Client::Errors;
use Couchbase::Client::IDXConst;
use Couchbase::Client::Return;

my $have_storable = eval "use Storable;";
my $have_zlib = eval "use Compress::Zlib";

use Array::Assign;

our $VERSION = '0.01_1';
XSLoader::load(__PACKAGE__, $VERSION);
{
    no warnings 'once';
    *gets = \&get;
}

sub make_compression_settings {
    my ($arglist,$options) = @_;
    
}

sub new {
    my ($pkg,$opts) = @_;
    my $server;
    my @arglist;
    my $servers = $opts->{servers};
    if(!$servers) {
        $server = $opts->{server};
    } else {
        $server = $servers->[0];
    }
    
    if(!$server) {
        die("Must have server");
    }
    arry_assign_i(@arglist,
        CTORIDX_SERVERS, $server,
        CTORIDX_USERNAME, $opts->{username},
        CTORIDX_PASSWORD, $opts->{password},
        CTORIDX_BUCKET, $opts->{bucket});
    my $o = $pkg->construct(\@arglist);
    my $errors = $o->get_errors;
    foreach (@$errors) {
        my ($errno,$errstr) = @$_;
        log_err($errstr);
    }
    return $o;
}

1;

__END__

=head1 NAME

Couchbase::Client - Perl Couchbase Client

=head1 SYNOPSIS

    use Couchbase::Client;
    use Couchbase::Client::Errors;
    
    my $client = Couchbase::Client->new({
        server => 'localhost:8091',
        username => 'some_user',
        password => 'secret',
        bucket => 'my_bucket'
    });
    
Possible connection errors:

    foreach my $err (@{$client->get_errors}) {
        my ($errnum,$errstr) = @$err;
        warn("Trouble ahead! Couchbase client says: $errstr.");
    }
    my $opret;
    
Simple get and set:

    $opret = $client->set(Hello => "World", 3600);
    if(!$opret->is_ok) {
        warn("Couldn't set 'Hello': ". $opret->errstr);
    }
    
    $opret = $client->get("Hello");
    if($opret->value) {
        printf("Got %s for 'Hello'\n", $opret->value);
    } else {
        warn("Couldn't get value for 'Hello': ". $opret->errstr);
    }
    
Update expiration:

    #make 'Hello' entry expire in 120 seconds
    $client->touch("Hello", 120);
    
Atomic CAS

    $opret = $client->get("Hello");
    if($opret->value && $opret->value != "Planet") {
        $opret = $client->cas(Hello => 'Planet', $opret->cas);
        
        #check if atomic set was OK:
        if(!$opret->is_ok) {
            warn("Couldn't update: ".$opret->errstr);
        }
    }
    
=head2 DESCRIPTION

<Couchbase::Client> is the client for couchbase (http://www.couchbase.org),
which is based partially on the C<memcached> server and the Memcache protocol.

In further stages, this module will attempt to retain backwards compatibility with
older memcached clients like L<Cache::Memcached> and L<Cache::Memcached::Fast>

This client is mainly written in C and interacts with C<libcouchbase> - the common
couchbase client library, which must be installed.

=head2 METHODS

All of the protocol methods (L</get>, L</set>, etc) return a common return value of
L<Couchbase::Client::Return> which stores operation-specific information and
common status.

For simpler versions of return values, see L<Couchbase::Client::Compat> which
tries to support the C<Cache::Memcached::*> interface.

=head3 new(\%options)

Create a new object. Takes a hashref of options. The following options are
currently supported

=over

=item server

The host and port of the couchbase server to connect to. If ommited, defaults to
C<localhost:8091>.

=item servers

Takes an arrayref of servers, currently only the first server is used, but this
will change.

=item username, password

Authentication credentials for the connection. Defaults to NULL

=item bucket

The bucket name for the connection. Defaults to C<default>

=back

=head3 get(key)

Retrieves the value stored under C<key>. Returns an L<Couchbase::Client::Return>
object.

If the key is not found on the server, the returned object's C<errnum> field
will be set to C<COUCHBASE_KEY_ENOENT>

=head3 append

=head3 prepend

=head3 set(key, value [,expiry])

Attempts to set, prepend, or append the value of the key C<key> to C<value>,
optionally setting an expiration time of C<expiry> seconds in the future.

Returns an L<Couchbase::Client::Return> object.

=head3 add(key, value [,expiry])

Store the value on the server, but only if the key does not already exist.

A <COUCHBASE_KEY_EEXISTS> will be set in the returned object's C<errnum>
field if the key does already exist.

See L</set> for explanation of arguments.

=head3 replace(key, value [,expiry])

Replace the value stored under C<key> with C<value>, but only
if the key does already exist on the server.

See L</get> for possible errors, and L</set> for argument description.


=head3 gets(key)

This is an alias to L</get>. The CAS value is returned on any C<get> operation.

=head3 cas(key, value, cas, [,expiry])

Tries to set the value of C<key> to C<value> but only if the opaque C<cas> is
equal to the CAS value on the server.

The <cas> argument is retrieved as such:

    my $opret = $client->get("Key");
    $client->set("Key", "Value", $opret->cas);
    
The last argument is the expiration offset as documented in L</set>

=head3 touch(key, expiry)

Modifies the expiration time of C<key> without fetching or setting it.

=head3 arithmetic(key, delta, initial [,expiry])

Performs an arithmetic operation on the B<numeric> value stored in C<key>.

The value will be added to C<delta> (which may be a negative number, in which
case, C<abs(delta)> will be subtracted).

If C<initial> is not C<undef>, it is the value to which C<key> will be initialized
if it does not yet exist.

=head3 incr(key [,delta])

=head3 decr(key [,delta])

Increments or decrements the numeric value stored under C<key>, if it exists.

If delta is specified, it is the B<absolute> value to be added to or subtracted
from the value. C<delta> defaults to 1.

These two functions are equivalent to doing:

    $delta ||= 1;
    $delta = -$delta if $decr;
    $o->arithmetic($key, $delta, undef);

=head4 NOTE ABOUT 32 BIT PERLS

If your Perl does not support 64 bit integer arithmetic, then L<Math::BigInt> will
be used for conversion. Since Couchbase internally represents both deltas and values
as C<int64_t> or C<uint64_t> values.

TODO: would be nice to optionally provide 32-bit integer overflow options for
performance.

=head3 delete(key [,cas])

=head3 remove(key [,cas])

These two functions are identical. They will delete C<key> on the server.

If C<cas> is also specified, the deletion will only be performed if C<key> still
maintains the same CAS value as C<cas>.


=head3 get_errors()

Returns a list of client/server errors which have ocurred during the last operation.

The errors here differ from the errors returned by normal operations, as the
operation errors provide status for a specific key, whereas C<get_errors> provide
status for the client connection in general.

The return value is an arrayref of arrayrefs in the following format:

    get_errors() == [
        [$errnum, $errstr],
        [$errnum, $errstr],
        ...
    ]
    
Modifications to the arrayref returned by C<get_errors> will be reflected in
future calls to this function, until a new operation is performed and the error
stack is cleared.

=head2 SEE ALSO

L<Couchbase::Client::Errors>

Status codes and their meanings.

L<Couchbase::Client::Compat> - subclass which conforms to the L<Cache::Memcached>
interface.

L<http://www.couchbase.org> - Couchbase.


=head1 AUTHOR & COPYRIGHT

Copyright (C) 2012 M. Nunberg

You may use and distributed this software under the same terms and conditions as
Perl itself.

