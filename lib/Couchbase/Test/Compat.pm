package Couchbase::Test::Compat;
use strict;
use warnings;
use base qw(Couchbase::Test::Common);
use Couchbase::Client;
use Couchbase::Client::Compat;
use Data::Dumper;
use Test::More;

sub setup_client :Test(startup) {
    my $self = shift;
    $self->mock_init();

    my %options = (
        %{$self->common_options}
    );

    my $o = Couchbase::Client::Compat->new(\%options);
    $self->cbo( $o );
}

sub cbo {
    if(@_ == 1) {
        return $_[0]->{object};
    } elsif (@_ == 2) {
        $_[0]->{object} = $_[1];
        return $_[1];
    }
}

sub T201_test_set :Test(no_plan)
{
    my $self = shift;
    my $rv;
    $rv = $self->cbo->set("key", "value");
    ok($rv, "Simple set returns OK");

    $rv = $self->cbo->set("key", "value", 1);
    ok($rv, "Set with expiry");

    $self->cbo->remove("non-exist-key");
    $rv = $self->cbo->get("key");
    is($rv, "value");
    ok($rv, "Get returns value itself");

    $rv = $self->cbo->get("non-exist-key");
    ok(!$rv, "get miss returns false");

    my $rvs;
}

sub T202_test_cas :Test(no_plan)
{
    my $self = shift;
    my $rv;
    my $cas;
    my $o = $self->cbo;

    $o->set("key", "value");
    $rv = $o->gets("key");
    isa_ok($rv, 'ARRAY');

    is($rv->[1], "value", "have value as first element");
    ok($rv->[0], "have CAS as second element");

    $rv = $o->cas("key", @$rv);
}

sub T203_test_multi :Test(no_plan)
{
    my $self = shift;
    my $o = $self->cbo;
    my $rvs;

    $o->set("key", "value");
    $o->remove("non-exist-key");

    $rvs = $self->cbo->get_multi("key", "non-exist-key");
    isa_ok($rvs, 'HASH', "get_multi returns hashref");

    is($rvs->{key}, "value", "get_multi in hashref returns proper found value");
    ok(exists ${$rvs}{"non-exist-key"},
       "non-exist-key present but false in hash");


    $o->set_multi(["key1", "value1"], ["key2", "value2"]);
    $rvs = $o->gets_multi("key1", "key2");

    my @cas_params;
    while (my ($k,$v) = each %$rvs) {
        push @cas_params, [ $k, @$v ];
    }

    $rvs = $o->cas_multi(@cas_params);
    my @errs = grep { !$_ } values %$rvs;
    is(@errs, 0, "No errors");
    is(scalar keys %$rvs, 2, "got all keys");
}


1;
