package Couchbase::Test::Settings;
use strict;
use warnings;
use base qw(Couchbase::Test::Common);
use Test::More;
use Couchbase::Client::Errors;
use Data::Dumper;

use Class::XSAccessor {
    accessors => [qw(cbo)]
};

sub setup_client :Test(startup)
{
    my $self = shift;
    $self->mock_init();
    
    my %options = (
        %{$self->common_options},
        compress_threshold => 100
    );
    
    my $o = Couchbase::Client->new(\%options);
    
    $self->cbo( $o );
}

sub T20_settings_connect :Test(no_plan)
{
    my $self = shift;
    
    my $client = Couchbase::Client->new({
        username => "bad",
        password => "12345",
        bucket => "nonexistent",
        no_init_connect => 1,
        server => '127.0.0.1:0'
    });
    is(scalar @{$client->get_errors()}, 0,
       "No error on initial connect with no_init_connect => 1");
    
    my $ret = $client->set("Foo", "Bar");
    is($ret->errnum, COUCHBASE_ETMPFAIL, "Got ETMPFAIL on non-connected server");
    
    ok(!$client->connect, "Failure to connect to nonexistent host");
    my $errors = $client->get_errors;
    ok(scalar @$errors, "Have error");
    is($errors->[0]->[0], COUCHBASE_NETWORK_ERROR, "Got NETWORK_ERROR");
    
    $client = Couchbase::Client->new({
        %{$self->common_options},
        bucket => 'nonexist'
    });
    $errors = $client->get_errors();
    ok(scalar @$errors, "Have error for nonexistent bucket");
    is($errors->[0]->[0], COUCHBASE_BUCKET_ENOENT,
       "Got BUCKET_ENOENT for nonexistent bucket");
}


sub T21_compress_settings :Test(no_plan)
{
    my $self = shift;
    my $v;
    
    $v = $self->cbo->enable_compress();
    ok($v, "Compression enabled by default");
    
    $v = $self->cbo->enable_compress(0);
    is($self->cbo->enable_compress, 0, "Compression disabled via setter");
}

1;