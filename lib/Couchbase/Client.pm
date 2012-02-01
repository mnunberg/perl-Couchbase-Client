package Couchbase::Client;

BEGIN {
    require XSLoader;
    our $VERSION = '0.01_1';
    XSLoader::load(__PACKAGE__, $VERSION);
}

use strict;
use warnings;

use Couchbase::Client::Errors;
use Couchbase::Client::IDXConst;
use Couchbase::Client::Return;

my $have_storable = eval "use Storable; 1;";
my $have_zlib = eval "use Compress::Zlib; 1;";

use Log::Fu;
use Array::Assign;

{
    no warnings 'once';
    *gets = \&get;
    *gets_multi = \&get_multi;
}

#this function converts hash options for compression and serialization
#to something suitable for construct()

sub _make_conversion_settings {
    my ($arglist,$options) = @_;
    my $compress_threshold = delete $options->{compress_threshold};
    my $flags = 0;
    
    $compress_threshold = 0 unless defined $compress_threshold;
    $compress_threshold = 0 if $compress_threshold < 0;
    $arglist->[CTORIDX_COMP_THRESHOLD] = $compress_threshold;
    
    my $meth_comp = 0;
    if(exists $options->{compress_methods}) {
        $meth_comp = delete $options->{compress_threshold};
    }
    if($meth_comp == 0 && $have_zlib) {
        $meth_comp = [ sub { ${$_[1]} = Compress::Zlib::memGzip(${$_[0]}) },
                      sub { ${$_[1]} = Compress::Zlib::memGunzip(${$_[0]}) }]
    }
    
    if($meth_comp) {
        $flags |= fUSE_COMPRESSION;
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
    
    $arglist->[CTORIDX_MYFLAGS] = $flags;
}

sub _MkCtorIDX {
    my $opts = shift;
    
    my $server;
    my @arglist;
    my $servers = delete $opts->{servers};
    if(!$servers) {
        $server = delete $opts->{server};
    } else {
        $server = $servers->[0];
    }
    
    if(!$server) {
        die("Must have server");
    }
    arry_assign_i(@arglist,
        CTORIDX_SERVERS, $server,
        CTORIDX_USERNAME, delete $opts->{username},
        CTORIDX_PASSWORD, delete $opts->{password},
        CTORIDX_BUCKET, delete $opts->{bucket});
    
    _make_conversion_settings(\@arglist, $opts);
    if(keys %$opts) {
        warn sprintf("Unused keys (%s) in constructor",
                     join(", ", keys %$opts));
    }
    return \@arglist;
}

sub new {
    my ($pkg,$opts) = @_;
    my $arglist = _MkCtorIDX($opts);
    
    my $o = $pkg->construct($arglist);
    my $errors = $o->get_errors;
    foreach (@$errors) {
        my ($errno,$errstr) = @$_;
        log_err($errstr);
    }
    return $o;
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

Takes an arrayref of servers, currently only the first server is used, but this
will change.

=item username, password

Authentication credentials for the connection. Defaults to NULL

=item bucket

The bucket name for the connection. Defaults to C<default>

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

=item I<serialize_methods>

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
exception (call I<die>).  The exception will be caught by the module
and L</get> will then pretend that the key hasn't been found.

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



=head3 get_multi(@keys)

=head3 get_multi(\@keys)

=head3 gets_multi

alias to L</get_multi>

=head3 touch_multi([key, exp]..)


=head3 set_multi([key => value, ...], [key => value, ...])


Performs multiple set operations on a multitude of keys. Input parameters are
array references. The contents of these array references follow the same
convention as calls to L</set> do. Thus:

    $o->set_multi(['Foo', 'foo_value', 120], ['Bar', 'bar_value']);

will set the key C<foo> to C<foo_value>, with an expiry of 120 seconds in the
future. C<bar> is set to C<bar_value>, without any expiry.

=head3 cas_multi([key => value, $cas, ...])

Multi version of L</cas>

=head3 arithmetic_multi([key => $delta, ...])

Multi version of L</arithmetic>

=head3 incr_multi(@keys)

=head3 decr_multi(@keys)

=head3 incr_multi( [key, amount], ... )

=head3 decr_multi( [key, amount], ... )


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

