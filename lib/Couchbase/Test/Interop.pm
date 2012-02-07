package Couchbase::Test::Interop;
use strict;
use warnings;
use base qw(Couchbase::Test::Common);
use Test::More;
use Couchbase::Client::Errors;
use Data::Dumper;
use Class::XSAccessor {
    accessors => [qw(cbo memds memd confua vbconf)]
};

my $MEMD_CLASS;
my $have_memcached = 
eval {
    require Cache::Memcached::Fast;
    $MEMD_CLASS = "Cache::Memcached::Fast";
} ||
eval {
    require Cache::Memcached;
    $MEMD_CLASS = "Cache::Memcached";
} ||
eval {
    require Cache::Memcached::libmemcached;
    $MEMD_CLASS = "Cache::Memcaced::libmemcached";
};


sub setup_client :Test(startup) {
    my $self = shift;
    if(!$have_memcached) {
        $self->SKIP_ALL("Need Cache::Memcached::libmemcached");
    }
    
    if(!$Couchbase::Test::Common::RealServer) {
        $self->SKIP_ALL("Need connection to real cluster");
    }
    
    if(!$Couchbase::Test::Common::MemdPort) {
        $self->SKIP_ALL("Need dedicated memcached proxy port");
    }

    $self->mock_init();
    my $server = $self->common_options->{server};
    
    my $username = $self->common_options->{username};
    my $password = $self->common_options->{password};
    
    my $cbo = Couchbase::Client->new({
        %{$self->common_options}
    });
    
    $self->cbo($cbo);
    
    my $memd = $MEMD_CLASS->new($self->memd_options);
    $self->memd($memd);
}

sub memd_for_key {
    my ($self,$key) = @_;
    return $self->memd;
}

sub T30_interop_init :Test(no_plan)
{
    my $self = shift;
    my $key = "Foo";
    my $value = "foo_value";
    
    my $memd = $self->memd;
    
    ok($memd->set($key, $value), "Set value OK");
    is($memd->get($key), $value, "Got back our value");
    
    my $ret = $self->cbo->get($key);
    ok($ret->is_ok, "Found value for memcached key");
    is($ret->value, $value, "Got back same value");
    
    $key = "bar";
    $value = "bar_value";
    
    ok($self->cbo->set($key,$value)->is_ok, "set via cbc");
    is($memd->get($key), $value, "get via memd");
}

sub T31_interop_serialization :Test(no_plan) {
    my $self = shift;
    my $key = "Serialized";
    my $value = [ qw(foo bar baz), { "this is" => "a hash" } ];
    my $memd = $self->memd_for_key($key);
    
    ok($memd->set($key, $value), "Set serialized structure");
    my $ret;
    $ret = $self->cbo->get($key);
    ok($ret->is_ok, "Got ok result");
    is_deeply($ret->value, $value, "Compared identical perl structures");
    is_deeply($memd->get($key), $ret->value,"even deeper comparison");
}

sub T32_interop_compression :Test(no_plan) {
    
}

1;