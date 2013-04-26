package Couchbase::Client;

BEGIN {
    require XSLoader;
    our $VERSION = '2.0.0_1';
    XSLoader::load(__PACKAGE__, $VERSION);
}

use strict;
use warnings;

use Couchbase::Client::Errors;
use Couchbase::Client::IDXConst;
use Couchbase::Client::Return;
use Couchbase::Client::Iterator;

my $have_storable = eval "use Storable; 1;";
my $have_zlib = eval "use Compress::Zlib; 1;";

use Array::Assign;

{
    no warnings 'once';
    *gets = \&get;
    *gets_multi = \&get_multi;
    *gets_multi_A = \&get_multi_A;

    *delete_multi = \&remove_multi;
    *delete_multi_A = \&remove_multi_A;
}

# Get the CouchDB (2.0) API
use Couchbase::Couch::Base;
use base qw(Couchbase::Couch::Base);

#this function converts hash options for compression and serialization
#to something suitable for construct()

sub _make_conversion_settings {
    my ($arglist,$options) = @_;
    my $flags = 0;


    $arglist->[CTORIDX_MYFLAGS] ||= 0;

    if($options->{dereference_scalar_ref}) {
        $arglist->[CTORIDX_MYFLAGS] |= fDEREF_RVPV;
    }

    if(exists $options->{deconversion}) {
        if(! delete $options->{deconversion}) {
            return;
        }
    } else {
        $flags |= fDECONVERT;
    }

    if(exists $options->{compress_threshold}) {
        my $compress_threshold = delete $options->{compress_threshold};
        $compress_threshold =
            (!$compress_threshold || $compress_threshold < 0)
            ? 0 : $compress_threshold;
        $arglist->[CTORIDX_COMP_THRESHOLD] = $compress_threshold;
        if($compress_threshold) {
            $flags |= fUSE_COMPRESSION;
        }
    }

    my $meth_comp;
    if(exists $options->{compress_methods}) {
        $meth_comp = delete $options->{compress_methods};
    } elsif($have_zlib) {
        $meth_comp = [ sub { ${$_[1]} = Compress::Zlib::memGzip(${$_[0]}) },
                      sub { ${$_[1]} = Compress::Zlib::memGunzip(${$_[0]}) }]
    }

    if(defined $meth_comp) {
        $arglist->[CTORIDX_COMP_METHODS] = $meth_comp;
    }

    my $meth_serialize = 0;
    if(exists $options->{serialize_methods}) {
        $meth_serialize = delete $options->{serialize_methods};
    }

    if($meth_serialize == 0 && $have_storable) {
        $meth_serialize = [ \&Storable::freeze, \&Storable::thaw ];
    }

    if($meth_serialize) {
        $flags |= fUSE_STORABLE;
        $arglist->[CTORIDX_SERIALIZE_METHODS] = $meth_serialize;
    }

    $arglist->[CTORIDX_MYFLAGS] |= $flags;
}

sub _MkCtorIDX {
    my $opts = shift;

    my @arglist;
    my $server = delete $opts->{server} or die "Must have server";
    arry_assign_i(@arglist,
        CTORIDX_SERVERS, $server,
        CTORIDX_USERNAME, delete $opts->{username},
        CTORIDX_PASSWORD, delete $opts->{password},
        CTORIDX_BUCKET, delete $opts->{bucket});

    _make_conversion_settings(\@arglist, $opts);

    my $tmp = delete $opts->{io_timeout} ||
            delete $opts->{select_timeout} ||
            delete $opts->{connect_timeout} ||
            delete $opts->{timeout};

    $tmp ||= 2.5;
    $arglist[CTORIDX_TIMEOUT] = $tmp if defined $tmp;
    $arglist[CTORIDX_NO_CONNECT] = delete $opts->{no_init_connect};


    if(keys %$opts) {
        warn sprintf("Unused keys (%s) in constructor",
                     join(", ", keys %$opts));
    }
    __PACKAGE__->_CouchCtorInit(\@arglist);
    return \@arglist;
}

sub new {
    my ($pkg,$opts) = @_;
    my $server_str;
    my $server_spec = $opts->{servers} || $opts->{server};

    if (ref $server_spec eq 'ARRAY') {
        $server_str = join(";", @$server_spec);
    } else {
        $server_str = $server_spec;
    }

    if (!$server_str) {
        die("Must have 'servers' or 'server'");
    }

    my $privopts = { %$opts };

    $privopts->{server} = $server_str;
    delete $privopts->{servers};
    my $arglist = _MkCtorIDX($privopts);
    my $self = $pkg->construct($arglist);
    return $self;
}

#This is called from within C to record our stats:
sub _stats_helper {
    my ($hash,$server,$key,$data) = @_;
    #printf("Got server %s, key%s\n", $server, $key);
    $key ||= "__default__";
    ($hash->{$server}->{$key} ||= "") .= $data;
}

1;

__END__

=head1 NAME

Couchbase::Client - Perl Couchbase Client

=head1 README

This page documents the API of C<Couchbase::Client>. To install this module,
see L<Couchbase::Client::README> for a broader overview.

See that same page for a list of current known issues as well.

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

View/MapReduce Operations

    # Create a design document

    my $ddoc = {
        '_id' => '_design/blog',
        language => 'javascript',
        views => {
            'recent-posts' => {
                map => 'function(d) { if(d.date) { emit(d.date, d.title); }}'
            }
        }
    };

    my $rv = $client->couch_design_put($ddoc);
    if (!$rv->is_ok) {
        # check for possible errors here..
    }

    # Now, let's load up some documents

    my @posts = (
        ["i-like-perl" => {
            title => "Perl is cool",
            date => "4/26/2013"
        }],
        ["couchbase-and-perl" => {
            title => "Couchbase::Client is super fast",
            date => "4/26/2013"
        }]
    );

    # This is a convenience around set_multi. It encodes values into JSON
    my $rvs = $client->couch_set_multi(@posts);

    # Now, query the view. We use stale = 'false' to ensure consistency

    $rv = $client->couch_view_slurp(['blog', 'recent-posts'], stale => 'false');

    # Now dump the rows to the screen.
    print Dumper($rv->value);

=head2 DESCRIPTION

C<Couchbase::Client> is the client for couchbase (http://www.couchbase.org),
which is based partially on the C<memcached> server and the Memcache protocol.

In further stages, this module will attempt to retain backwards compatibility with
older memcached clients like L<Cache::Memcached> and L<Cache::Memcached::Fast>

This client is mainly written in C and interacts with C<libcouchbase> - the common
couchbase client library, which must be installed.

=head2 BASIC METHODS

All of the protocol methods (L</get>, L</set>, etc) return a common return value of
L<Couchbase::Client::Return> which stores operation-specific information and
common status.

For simpler versions of return values, see L<Couchbase::Client::Compat> which
tries to support the C<Cache::Memcached::*> interface.

=head3 new(\%options)

Create a new object. Takes a hashref of options. The following options are
currently supported

=head4 Typical Constructor Options

=over

=item server

The host and port of the couchbase server to connect to. If ommited, defaults to
C<localhost:8091>.

=item servers

A list of servers to try, in order. C<Couchbase::Client> will connect to the first
responsive server (optionally complaining with warnings about failed servers).

This is a special construction-time option. It will not work in conjunction with
the L</no_init_connect> option.

By virtue of the design of the Couchbase architecture, already-connected clients
will learn about alternate entry points once an initial entry into the cluster
has been established. Therefore if a connection fails in-situ, the client is
likely to know of alternate entry points, and thus the server list is only
useful for discovering the initial entry point.

=item username, password

Authentication credentials for the connection. Defaults to NULL

=item bucket

The bucket name for the connection. Defaults to C<default>

=item io_timeout

=item connect_timeout

=item select_timeout

=item timeout

These all alias to the same setting, and control the time the client waits
for a response after it sends a request to the server.

The value should be specified in seconds (fractional values are allowed)

Defaults to C<2.5>


=back

=head4 Conversion Options

The following options for conversion can be specified. Some of the compression
code is borrowed from L<Cache::Memcached::Fast>, with some modifications.

First, a note about compression and conversion:

Compression and conversion as done by legacy memcached clients in Perl and other
languages relies on internal 'user-defined' protocol flags. Meaning, that the flags
are free for use by any client implementation. These flags are of course not
exposed to you, the end user, but it's worth reading about them.

Legacy clients have used 'standard' flags for compression and serialization -
flags which themselves only make sense to other hosts running the same client
with the same understanding of the flag semantics.

What this means for you:

=over

=item Storable-incompatibility and interoperability

When serializing a complex object, the default is to use L<Storable>. Storable
itself is ill-suited for cross-platform, cross-machine and cross-version storage.

Additionally, the flags set by other Perl clients to indicate C<Storable> is the
same flag used by other memcached clients in other languages to indicate other
forms of serialization and/or compression.

Therefore it is highly unrecommended to use Storable if you want any other host
to be able to access your key. If you are sure that all your hosts are running
the same version of Storable on the same architecture then it might not fail.

Having said that, Storable is still enabled by default in order to retain
drop-in compatibility with older clients.

=item Compression

Most clients have used the same flag to indicate Gzip compression. While legacy
clients (L<Cache::Memcached> and friends) provide options to provide your 'own'
compression mechanism, this compression mechanism must be used throughout all
hosts wishing to read and write to the key

=item Appending, Prepending

Compression and serialization are ill-suited for values which may be modified
using L</append> and L</prepend>. Specifically the server will blindly append
the data provided (in I<byte> form) to the already-stored value.

=back

Now, without further ado, we present conversion options, mostly copy-pasted from
L<Cache::Memcached::Fast>

=over

=item compress_threshold

  compress_threshold => 10_000
  (default: -1)

The value is an integer.  When positive it denotes the threshold size
in bytes: data with the size equal or larger than this should be
compressed.  See L</compress_ratio> and L</compress_methods> below.

Non-positive value disables compression.

=item compress_methods

  compress_methods => [ \&IO::Compress::Gzip::gzip,
                        \&IO::Uncompress::Gunzip::gunzip ]
  (default: [ sub { ${$_[1]} = Compress::Zlib::memGzip(${$_[0]}) },
              sub { ${$_[1]} = Compress::Zlib::memGunzip(${$_[0]}) } ]
   when Compress::Zlib is available)

The value is a reference to an array holding two code references for
compression and decompression routines respectively.

Compression routine is called when the size of the I<$value> passed to
L</set> method family is greater than or equal to
L</compress_threshold>.  The fact that
compression was performed is remembered along with the data, and
decompression routine is called on data retrieval with L</get> method
family.  The interface of these routines should be the same as for
B<IO::Compress> family (for instance see
L<IO::Compress::Gzip::gzip|IO::Compress::Gzip/gzip> and
L<IO::Uncompress::Gunzip::gunzip|IO::Uncompress::Gunzip/gunzip>).
I.e. compression routine takes a reference to scalar value and a
reference to scalar where compressed result will be stored.
Decompression routine takes a reference to scalar with compressed data
and a reference to scalar where uncompressed result will be stored.
Both routines should return true on success, and false on error.

By default we use L<Compress::Zlib|Compress::Zlib> because as of this
writing it appears to be much faster than
L<IO::Uncompress::Gunzip|IO::Uncompress::Gunzip>.

=item serialize_methods

  serialize_methods => [ \&Storable::freeze, \&Storable::thaw ],
  (default: [ \&Storable::nfreeze, \&Storable::thaw ])

The value is a reference to an array holding two code references for
serialization and deserialization routines respectively.

Serialization routine is called when the I<$value> passed to L</set>
method family is a reference.  The fact that serialization was
performed is remembered along with the data, and deserialization
routine is called on data retrieval with L</get> method family.  The
interface of these routines should be the same as for
L<Storable::nfreeze|Storable/nfreeze> and
L<Storable::thaw|Storable/thaw>.  I.e. serialization routine takes a
reference and returns a scalar string; it should not fail.
Deserialization routine takes scalar string and returns a reference;
if deserialization fails (say, wrong data format) it should throw an
exception (call I<die>). The exception will be caught by the module
and L</get> will then pretend that the key hasn't been found.

=item deconversion

    deconversion => 1
    (default: deconversion => 1)

Controls whether I<de>-compression and I<de>-serialization are performed on
apparently serialized or compressed values.

Default is enabled.

=item dereference_scalar_ref

    dereference_scalar_ref => 1
    (default: dereference_scalar_ref => 0)

Controls whether a SCALAR reference is 'serialized' as normal via storable,
or whether it should be dereferenced, and its underlying string used as a plain
scalar value.

=back

=head3 get(key)

Retrieves the value stored under C<key>. Returns an L<Couchbase::Client::Return>
object.

If the key is not found on the server, the returned object's C<errnum> field
will be set to C<COUCHBASE_KEY_ENOENT>

=head3 append(key, value_to_append, [ , expiry] )

=head3 append(key, value_to_append, { cas => $cas, exp => $expiry })

=head3 prepend(key, value_to_prepend, [ , expiry ])

=head3 prepend(key, value_to_prepend, { cas => $cas, exp => $expiry })

=head3 set(key, value [,expiry])

=head3 set(key, value, { cas => $cas, exp => $expiry })

Attempts to set, prepend, or append the value of the key C<key> to C<value>,
optionally setting an expiration time of C<expiry> seconds in the future.

Returns an L<Couchbase::Client::Return> object.

=head3 add(key, value [,expiry])

=head3 add(key, value, { exp => $expiry })

Store the value on the server, but only if the key does not already exist.

A <COUCHBASE_KEY_EEXISTS> will be set in the returned object's C<errnum>
field if the key does already exist.

See L</set> for explanation of arguments.

=head3 replace(key, value [,expiry])

=head3 replace(key, value, { cas => $cas, exp => $expiry })

Replace the value stored under C<key> with C<value>, but only
if the key does already exist on the server.

See L</get> for possible errors, and L</set> for argument description.



=head3 gets(key)

This is an alias to L</get>. The CAS value is returned on any C<get> operation.

=head3 cas(key, value, cas, [,expiry])

=head3 cas(key, value, cas, { exp => $expiry })

Tries to set the value of C<key> to C<value> but only if the opaque C<cas> is
equal to the CAS value on the server.

The <cas> argument is retrieved as such:

    my $opret = $client->get("Key");
    $client->set("Key", "Value", $opret->cas);

The last argument is the expiration offset as documented in L</set>

=head3 touch(key, expiry)

Modifies the expiration time of C<key> without fetching or setting it.

=head3 arithmetic(key, delta, initial [,expiry])

=head3 arithmetic(key, delta, { exp => $expiry })

Performs an arithmetic operation on the B<numeric> value stored in C<key>.

The value will be added to C<delta> (which may be a negative number, in which
case, C<abs(delta)> will be subtracted).

If C<initial> is not C<undef>, it is the value to which C<key> will be initialized
if it does not yet exist.

=head3 incr(key [,delta])

=head3 incr(key, { delta => $delta, initial => $initial, exp => $expiry })

=head3 decr(key [,delta])

=head3 decr(key, { delta => $delta, initial => $initial, exp => $expiry })

Increments or decrements the numeric value stored under C<key>, if it exists.

If delta is specified, it is the B<absolute> value to be added to or subtracted
from the value. C<delta> defaults to 1.

If C<initial> is specified, it will be initialized to this value if the key does
not exist (and C<delta> is ignored).

These two functions are equivalent to doing:

    $delta ||= 1;
    $delta = -$delta if $decr;
    $o->arithmetic($key, $delta, undef);

If C<initial> is used

=head4 NOTE ABOUT 32 BIT PERLS

If Perl does not support 64 bit integers then the following will happen:

If the result of an arithmetic operation can be stored within a 32 bit integer,
then all proceeds as normal and you get a normal Perl integer back. If, however
the result exceeds 32 bits (i.e. greated than stdint.h's C<UINT32_MAX>) then
your return value will be B<stringified>, since the underlying C layer can always
deal with 64 bit integers.

=head3 delete(key [,cas])

=head3 remove(key [,cas])

=head3 remove(key, { cas => $cas })

These two functions are identical. They will delete C<key> on the server.

If C<cas> is also specified, the deletion will only be performed if C<key> still
maintains the same CAS value as C<cas>.


=head3 lock(key, lock_time)

Lock the key on the server for the given C<lock_time>. During this time, any
attempts to lock the key again will fail with the error C<COUCHBASE_ETMPFAIL>.
Attempts to modify the key via one of the mutation methods (e.g. L</set>) will
fail with C<COUCHBASE_KEY_EEXISTS>.

You may unlock the key by using L</unlock>

=head3 unlock(key, cas)

Unlock the key using the provided C<cas>. The CAS must be the one returned from
the last L</lock> operation. Passing a stale CAS will fail with
C<COUCHBASE_ETMPFAIL>; unlocking a non-locked key will also fail with
C<COUCHBASE_ETMPFAIL>.

=head2 MULTI METHODS

These methods gain performance and save on network I/O by batch-enqueueing
operations.

Of these, only the C<get> and C<touch> methods currently do 'true' multi batching.

The other commands are still batched internally in the XS code, saving on xsub
call overhead.

All of these functions return a hash reference, whose keys are the keys specified
for the operation, and whose values are L<Couchbase::Client::Return> objects
specifying the result of the operation for that key.

Calling the multi methods generally involves passing a series of array references.
Each n-tuple passed in the list should contain arguments conforming to the
calling convention of the non-multi command variant.

Thus, where you would do:

    $rv = $o->foo($arg1, $arg2, $arg3)

The C<_multi> version would be

    $rvs = $o->foo_multi(
        [$arg1_0, $arg2_0, $arg3_0],
        [$arg1_1, $arg2_1, $arg3_1],
    );

The n-tuples themselves may either be grouped into a 'list', or an array reference
itself:

    my @arglist = map { [$h->{key}, $k->{value} ] };

    $o->set(@arglist);

    #the same as:

    $o->set( [ map [ { $h->{key}, $h->{value } ] }] );

    #and the same as:

    $o->set(map{ [$h->{key}, $h->{value}] });


As a convenience, if your argument list is in the form of an arrayref, rather
than a simple array, you can use the more efficient C<*_multi_A> calls. These
calls work just like the C<*_multi> variants, except that they only accept a
single argument which is an arrayref of "argument -ntuples".

Therefore, suppose you have a data structure which looks like this

    my $set_args = [ ["key1", "value1"], ["key2", "value2"] ]

You can now do

    my $rvs = $o->set_multi_A($set_args);

rather than

    my $rvs = $o->set_multi(@$set_args);

This is more efficient as the argument list is wrapped internally into an array
reference anyway.


For functions which only require a key, you may pass a list of keys to the
function, thus not requiring each key to be a single-element array ref. Likewise,
the C<*_multi_A> variant can accept an array ref of keys.


=head3 get_multi(@keys)

=head3 get_multi([$key1], [$key2])

=head3 get_multi_A([[$key1], [$key2]])

=head3 gets_multi

alias to L</get_multi>

=head3 get_iterator(@keys)

=head3 get_iterator([$key1], [$key2])

=head3 get_iterator_A(\@keys)

=head3 get_iterator_A([[$key1], [$key2]])

Takes the same form of arguments as C<get_multi>, but returns a
L<Couchbase::Client::Iterator> object instead of a result set. This allows you
to do L<DBI>-style iterative fetching of results while potentially reaping
the performance benefits of the multi protocol

=head3 touch_multi([key, exp]..)

=head3 touch_multi_A([[key, exp], ...])


=head3 set_multi([key => value, ...], [key => value, ...])

=head3 set_multi_A([[key => value], ...])

Performs multiple set operations on a multitude of keys. Input parameters are
array references. The contents of these array references follow the same
convention as calls to L</set> do. Thus:

    $o->set_multi(['Foo', 'foo_value', 120], ['Bar', 'bar_value']);

will set the key C<foo> to C<foo_value>, with an expiry of 120 seconds in the
future. C<bar> is set to C<bar_value>, without any expiry.

=head3 cas_multi([key => value, $cas, ...])

=head3 cas_multi_A([[key => value, $cas], ...])

Multi version of L</cas>

=head3 arithmetic_multi([key => $delta, ...])

=head3 arithmetic_multi_A([[key => $delta, ...], ...])

Multi version of L</arithmetic>

=head3 incr_multi(@keys)

=head3 incr_multi([$key, $options], ...)

=head3 incr_multi_A(\@keys)

=head3 incr_multi_A([[$key, $options], ...])

Multi version of L</incr>


=head3 decr_multi(@keys)

=head3 decr_multi([$key, $options], ...)

=head3 decr_multi_A(\@keys)

=head3 decr_multi_A([[$key, $options], ...])

Multi version of L</decr>


=head3 remove_multi(@keys)

=head3 remove_multi([$key, $options], ...)

=head3 remove_multi_A(\@keys)

=head3 remove_multi_A([[$key, $options], ...])

Multi version of L</remove>


=head3 unlock_multi([$key, $cas], ...)

=head3 unlock_multi_A([[$key, $cas]])

Multi version of L</unlock>


=head3 lock_multi([$key, $timeout], ...)

=head3 lock_multi_A([[$key, $timeout, ...]])

Multi version of L</lock>


=head2 RUNTIME SETTINGS

The following methods can be called without an argument, in which case it acts
as a getter, and returns the boolean status of the relevant setting.

If called with a single argument, that argument is a boolean value and the
method acts as a mutator. The old value for the setting is returned.


=head3 enable_compress(...), compression_settings(...)

=head3 serialization_settings(...)

These methods, when called with no arguments, will return the boolean status about
whether compression or serialization is enabled.

If passed an argument, the argument is converted to a boolean value, and the
previous setting is returned.

C<enable_compress> is an alias to C<compression_settings>, for API familiarity
with older clients.

=head3 conversion_settings(...)

This is a catch-all setting for all modes of conversion; i.e. serialization
B<and> compression. Disabling conversion will disable compression and serialization.

Enabling conversion will restore the previous serialization and compression
settings.

=head3 deconversion_settings(...)

This controls and accesses the deconversion setting. Deconversion is any
I<decompression> or I<deserialization> when retrieving a remote value. This can
be particularly handy if you wish to perform more heuristics on the type of
the value, rather than possibly have the deconversion settings fail.

When deconversion is disabled, all conversion settings are disabled as well.

=head3 compress_threshold(...)

Gets or sets the compression threshold, i.e. the minimum value length before
compression is applied.


=head3 timeout(...)

Get or set the timeout for enqueued operations. The timeout is the time the client
waits for a response after sending the request to the server.

Timeouts cannot be disabled. See documentation on constructor options.


=head2 INFORMATIONAL METHODS

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

=head3 stats( [keys, ..] )

=head3 stats()

Get statistics from all servers in the cluster.

If C<[keys..]> are specified, only the named keys will be gathered and returned

The return format is as so:

    {
        'server_name' => {
            'key_name' => 'key_value',
            ...
        },

        ...
    }


=head3 cluster_nodes()

Returns an array of cluster nodes. Each element of the array is a string
containing the hostname or IP of a cluster node.

=head3 lcb_version()

Returns the version information of the backing C<libcouchbase> library.
The return value is an array; the first element contains the string version,
i.e. C<'2.0.5'>, and the second element contains the second number, e.g.
C<0x020005>

=head2 VIEW QUERY METHODS


=head3 couch_design_put($json)

=head3 couch_design_get($name)

=head3 couch_view_slurp($view, $options)

=head3 couch_view_iterator($view, $options)

See L<Couchbase::Couch::Base> for a detailed overview of these methods

=head2 SEE ALSO

L<Couchbase::Client::Errors>

Status codes and their meanings.

L<Couchbase::Client::Compat> - subclass which conforms to the L<Cache::Memcached>
interface.

L<http://www.couchbase.org> - Couchbase.


=head1 AUTHOR & COPYRIGHT

Copyright (C) 2012, 2013 M. Nunberg

You may use and distributed this software under the same terms and conditions as
Perl itself.
