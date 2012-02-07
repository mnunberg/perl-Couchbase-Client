package Couchbase::Test::Interop;
use strict;
use warnings;
use base qw(Couchbase::Test::Common);
use Test::More;
use Couchbase::Client::Errors;
use Data::Dumper;
use Class::XSAccessor {
    accessors => [qw(cbo memds confua vbconf)]
};

my $MEMD_CLASS;
my $have_memcached = 
eval {
    require Cache::Memcached::libmemcached;
    $MEMD_CLASS = "Cache::Memcached::libmemcached";
};

my $have_libvbucket = eval 'use Couchbase::VBucket; 1;';
my $have_couchconf = eval 'use Couchbase::Config::UA; 1;';

if(!$have_memcached) {
    __PACKAGE__->SKIP_ALL("Need Cache::Memcached::libmemcached");
}
if(!$have_libvbucket) {
    __PACKAGE__->SKIP_ALL("Need Couchbase::VBucket");
}
if(!$have_couchconf) {
    __PACKAGE__->SKIP_ALL("Need Couchbase::Config::UA");
}

sub setup_client :Test(startup) {
    my $self = shift;
    $self->mock_init();
    my $server = $self->common_options->{server};
    
    my $username = $self->common_options->{username};
    my $password = $self->common_options->{password};
    
    my $cbo = Couchbase::Client->new({
        %{$self->common_options}
    });
    
    $self->cbo($cbo);
    
    my $confua = Couchbase::Config::UA->new(
        $server, username => $username, password => $password);
    
    #Get the actual memcached ports:
    my $default_pool = $confua->list_pools();
    my $pool_info = $confua->pool_info($default_pool);
    my $buckets = $confua->list_buckets($pool_info);
    
    my $selected_bucket = (grep($_->name eq $self->common_options->{bucket},
                               @$buckets))[0];
    
    die("Cannot find selected bucket") unless defined $selected_bucket;
    my $vbconf = $selected_bucket->vbconf();
    $self->vbconf($vbconf);
    $self->memds({});
}

sub memd_for_key {
    my ($self,$key) = @_;
    my $server = $self->vbconf->map($key);
    die("Couldn't map key!") unless $server;
    my $memd = $self->memds->{$server};
    if(!$memd) {
        $memd = $MEMD_CLASS->new({servers => [$server] } );
        eval { $memd->set_binary_protocol(1) };
        $self->memds->{$server} = $memd;
        note "Created new memcached object for $server";
    }
    return $memd;
}

sub T30_interop_init :Test(no_plan)
{
    my $self = shift;
    my $key = "Foo";
    my $value = "foo_value";
    
    my $memd = $self->memd_for_key($key);
    
    ok($memd->set($key, $value), "Set value OK");
    is($memd->get($key), $value, "Got back our value");
    
    my $ret = $self->cbo->get($key);
    ok($ret->is_ok, "Found value for memcached key");
    is($ret->value, $value, "Got back same value");
    #print Dumper($ret);
}

1;