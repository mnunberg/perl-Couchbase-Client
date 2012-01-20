package Couchbase::Client;
require XSLoader;
use strict;
use warnings;

use Couchbase::Client::Errors;
use Couchbase::Client::IDXConst;
use Couchbase::Client::Return;


use Log::Fu { level => "debug" };
use Array::Assign;

our $VERSION = '0.01_1';
XSLoader::load(__PACKAGE__, $VERSION);
{
    no warnings 'once';
    *gets = \&get;
}

sub v_debug {
    my ($self,$key) = @_;
    my $ret = $self->get($key);
    log_info($ret);
    my $value = $ret->value;
    if(defined $value) {
        log_infof("Got %s=%s OK", $key, $value);
    } else {
        log_errf("Got error for %s: %s (%d)", $key,
                 $ret->errstr, $ret->errnum);
        my $errors = $self->get_errors;
        foreach my $errinfo (@$errors) {
            my ($errnum,$errstr) = @$errinfo;
            log_errf("%s (%d)", $errstr,$errnum);
        }
    }
}

sub k_debug {
    my ($self,$key,$value) = @_;
    #log_debug("k=$key,v=$value");
    my $status = $self->set($key, $value);
    if($status->[RETIDX_ERRNUM] == COUCHBASE_SUCCESS) {
        log_infof("Setting %s=%s OK", $key, $value);
    } else {
        my $errors = $self->get_errors;
        foreach my $errinfo (@$errors) {
            my ($errnum,$errstr) = @$errinfo;
            log_errf("%s (%d)", $errstr,$errnum);
        }

        log_errf("Setting %s=%s ERR: %s (%d)",
                 $key, $value,
                 $status->[RETIDX_ERRSTR], $status->[RETIDX_ERRNUM]);
    }
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

if(!caller) {
    my $o = __PACKAGE__->new({
        server => '10.0.0.99:8091',
        username => 'Administrator',
        password => '123456',
        #bucket  => 'nonexist',
        bucket => 'membase0'
    });
    my @klist = qw(Foo Bar Baz Blargh Bleh Meh Grr Gah);
    $o->k_debug($_, $_."Value") for @klist;
    $o->v_debug($_) for @klist;
    $o->v_debug("NonExistent");
    $o->set("foo", "bar", 100);   
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

=head3 set(key, value [,expiry])

Attempts to set the value of the key C<key> to C<value>, optionally setting an
expiration time of C<expiry> seconds in the future.

Returns an L<Couchbase::Client::Return> object.

maybe a 'legacy' option will be provided to return a simple return value, like
older memcached clients

=head3 get(key)

Retrieves the value stored under C<key>. Returns an L<Couchbase::Client::Return>
object.

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

=head1 AUTHOR & COPYRIGHT

Copyright (C) 2012 M. Nunberg

You may use and distributed this software under the same terms and conditions as
Perl itself.

