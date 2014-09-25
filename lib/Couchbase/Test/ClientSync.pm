package Couchbase::Test::ClientSync;
use strict;
use warnings;
use base qw(Couchbase::Test::Common);
use Test::More;
use Couchbase::Client;
use Couchbase::Constants;
use Data::Dumper;

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
    $self->{basic_keys} = [qw(
        Foo Bar Baz Blargh Bleh Meh Grr Gah)];
}

sub cbo {
    if(@_ == 1) {
        return $_[0]->{object};
    } elsif (@_ == 2) {
        $_[0]->{object} = $_[1];
        return $_[1];
    }
}

sub err_ok {
    my $self = shift;
    my $errors = $self->cbo->get_errors;
    my $nerr = 0;
    foreach my $errinfo (@$errors) {
        $nerr++;
    }
    ok($nerr == 0, "Got no errors");
}

sub k2v {
    my ($self,$k) = @_;
    reverse($k);
}

sub v2k {
    my ($self,$v) = @_;
    reverse($v);
}

sub set_ok {
    my ($self,$msg,@args) = @_;
    my $ret = $self->cbo->set(@args);
    ok($ret->is_ok, $msg);
    $self->err_ok();
    if(!$ret->is_ok) {
        diag($ret->errstr);
    }
}

sub get_ok {
    my ($self,$key,$expected) = @_;
    my $ret = $self->cbo->get($key);
    ok($ret->is_ok, "Status OK for GET($key)");
    ok($ret->value eq $expected, "Got expected value for $key");
}

sub T00_set_values_simple :Test(no_plan) {
    my $self = shift;
    $self->err_ok();
    foreach my $k (@{$self->{basic_keys}}) {
        $self->set_ok("Key '$k'", $k, $self->k2v($k));
        $self->get_ok($k, $self->k2v($k))
    }
}

sub T01_get_nonexistent :Test(no_plan) {
    my $self = shift;
    my $v = $self->cbo->get('NonExistent');
    is($v->errnum, COUCHBASE_KEY_ENOENT, "Got ENOENT for nonexistent key");
    $self->err_ok();
}

sub T02_mutators :Test(no_plan) {
    my $self = shift;
    my $o = $self->cbo;

    my $key = "mutate_key";
    $o->remove($key); #if it already exists
    is($o->add($key, "BASE")->errnum, 0, "No error for add on new key");
    is($o->prepend($key, "PREFIX_")->errnum, 0, "No error for prepend");
    is($o->append($key, "_SUFFIX")->errnum, 0, "No error for append");
    is($o->get($key)->value, "PREFIX_BASE_SUFFIX", "Got expected mutated value");
}

sub T03_arithmetic :Test(no_plan) {
    my $self = shift;
    my $o = $self->cbo;
    my $key = "ArithmeticKey";
    $o->remove($key);
    my $wv;

    $wv = $o->arithmetic($key, -12, 42);
    ok($wv->is_ok, "Set arithmetic with initial value");

    $o->remove($key);

    $wv = $o->arithmetic($key, -12, undef);
    is($wv->errnum, COUCHBASE_KEY_ENOENT, "Error without initial value (undef)");

    $wv = $o->arithmetic($key, -12, 0, 120);
    ok($wv->is_ok, "No error with initial value=0");
    is($wv->value, 0, "Initial value is 0");

    $wv = $o->incr($key);
    is($wv->value, 1, "incr() == 1");

    $wv = $o->decr($key);
    is($wv->value, 0, "decr() == 0");
}

sub T04_atomic :Test(no_plan) {
    my $self = shift;
    my $o = $self->cbo;
    my $key = "AtomicKey";
    $o->delete($key);

    is($o->replace($key, "blargh")->errnum, COUCHBASE_KEY_ENOENT,
       "Can't replace non-existent value");

    my $wv = $o->set($key, "initial");
    ok($wv->errnum == 0, "No error");
    ok(length($wv->cas), "Have cas");
    $o->set($key, "next");
    my $newv = $o->cas($key, "my_next", $wv->cas);

    is($newv->errnum,
       COUCHBASE_KEY_EEXISTS, "Got EEXISTS for outdated CAS");

    $newv = $o->get($key);
    ok($newv->cas, "Have CAS for new value");
    $wv = $o->cas($key, "synchronized", $newv->cas);
    ok($wv->errnum == 0, "Got no error for CAS with updated CAS");
    is($o->get($key)->value, "synchronized", "Got expected value");

    $o->delete($key);
    ok($o->add($key, "value")->is_ok, "No error for ADD with nonexistent key");
    is($o->add($key, "value")->errnum,
       COUCHBASE_KEY_EEXISTS, "Got eexists for ADD on existing key");

    ok($o->delete($key, $newv->cas)->errnum, "Got error for DELETE with bad CAS");
    $newv = $o->get($key);
    ok($o->delete($key, $newv->cas)->errnum == 0,
       "No error for delete with updated CAS");
}

sub T05_conversion :Test(no_plan) {
    my $self = shift;
    my $o = $self->cbo;
    my $structure = [ qw(foo bar baz) ];
    my $key = "Serialization";
    my $rv;

    ok($o->set($key, $structure)->is_ok, "Serialized OK");

    $rv = $o->get($key);
    ok($rv->is_ok, "Got serialized structure OK");
    is_deeply($rv->value, $structure, "Got back our array reference");
    eval {
        $o->append($key, $structure);
    };
    ok($@, "Got error for append/prepending a serialized structure ($@)");
}

sub _multi_check_ret {
    my ($rv,$keys) = @_;
    my $nkeys = scalar @$keys;
    my $defined = scalar grep defined $_, values %$rv;
    my $n_ok = scalar grep $_->is_ok, values %$rv;

    is(scalar keys %$rv, $nkeys, "Expected number of keys");
    is($defined, $nkeys, "All values defined");
    is($n_ok,$nkeys, "All returned ok (no errors)");

}

sub multi_ok {
    my ($rv, $msg, $expect) = @_;
    my @errs;

    if ($expect) {
        @errs = grep {$_->errnum != $expect} values %$rv;
    } else {
        @errs = grep { !$_->is_ok } values %$rv;
    }

    ok(!@errs, $msg);
}

sub T06_multi :Test(no_plan) {
    my $self = shift;
    my $o = $self->cbo;
    my @keys = @{$self->{basic_keys}};

    my $rv = $o->set_multi(
        map { [$_, $_] } @keys);

    ok($rv && ref $rv eq 'HASH', "Got hash result for multi operation");
    ok(scalar keys %$rv == scalar @keys,
       "got expected number of results");

    is(grep(defined $_, values %$rv), scalar @keys, "All values defined");
    is(scalar grep(!$rv->{$_}->is_ok, @keys), 0, "No errors");

    $rv = $o->get_multi(@keys);
    _multi_check_ret($rv, \@keys);

    is(scalar grep($rv->{$_}->value eq $_, @keys), scalar @keys,
       "get_multi: Got expected values");

    $rv = $o->cas_multi(
        map { [$_, scalar(reverse $_), $rv->{$_}->cas ] } @keys );
    _multi_check_ret($rv, \@keys);

    #Remove them all:

    note "Remove (no CAS)";
    $rv = $o->remove_multi(@keys);
    _multi_check_ret($rv, \@keys);

    $rv = $o->set_multi(map { [$_, $_] } @keys);
    _multi_check_ret($rv, \@keys);

    note "Remove (with CAS)";
    $rv = $o->remove_multi(map { [ $_, $rv->{$_}->cas] } @keys);
    _multi_check_ret($rv, \@keys);

    note "Trying arithmetic..";

    $rv = $o->arithmetic_multi(
         map { [$_, 666, undef, 120] } @keys
    );
    ok(scalar(
        grep {$_->errnum == COUCHBASE_KEY_ENOENT} values %$rv
        ) == scalar @keys,
       "ENOENT for non-existent deleted arithmetic keys");


    #try arithmetic again:
    $rv = $o->arithmetic_multi(
        map { [$_, 666, 42, 120] } @keys);
    _multi_check_ret($rv, \@keys);

    is(scalar grep($_->value == 42, values %$rv), scalar @keys,
       "all keys have expected value");

    $rv = $o->incr_multi(@keys);
    _multi_check_ret($rv, \@keys);

    is(scalar grep($_->value == 43, values %$rv), scalar @keys,
       "all keys have been incremented");

    $rv = $o->decr_multi(
        map {[ $_, 41 ]} @keys);
    _multi_check_ret($rv, \@keys);
    is(scalar grep($_->value == 2, values %$rv), scalar @keys,
       "all keys have been decremented");
}

sub T06_multi_GH4 :Test(no_plan) {
    my $self = shift;
    my $o = $self->cbo;
    my $rv = $o->set_multi(['single_key', 'single_value']);
    ok($rv->{"single_key"}->is_ok, "Single arrayref on setmulti does not fail");
}

sub T06_multi_PLCBC_1 :Test(no_plan) {
    my $self = shift;
    my $o = $self->cbo;
    $o->set_multi(["key", "value"]);
    my $rv = $o->get_multi("single_key");
    ok($rv->{"single_key"}->is_ok, "Does not crash");
}

sub T06_multi_argtypes :Test(no_plan)
{
    my $self = shift;
    my $o = $self->cbo;
    my @keys = qw(foo bar baz);
    my @set_args = map { [$_, $_ ] } @keys;
    my $k1 = $keys[0];

    multi_ok($o->set_multi(@set_args), "set_multi - multiple argrefs");
    multi_ok($o->set_multi([$k1, $k1]), "set_multi - single argref");
    multi_ok($o->set_multi_A([[$k1, $k1]]), "set_multi_A");

    multi_ok($o->get_multi([$k1]), "get_multi. single arg ref");
    multi_ok($o->get_multi($k1), "get_multi. single key");
    multi_ok($o->get_multi(@keys), "get_multi, key list");
    multi_ok($o->get_multi(map { [$_] } @keys), "get_multi, key arrayrefs");

    multi_ok($o->get_multi_A([$k1]), "get_multi_A, single arrayref");
    multi_ok($o->get_multi_A([[$k1]]), "get_mutli_A - nested arrayref");
    multi_ok($o->get_multi_A(\@keys), "get_multi, arrayrefs of keys");

    if ( !($self->mock && $self->mock->nodes) ) {
        my $lock_rvs = $o->lock_multi(map {[$_, 10]} @keys);
        multi_ok($lock_rvs, "lock_multi");

        my $unlock_rvs = $o->unlock_multi(
            map { [ $_, $lock_rvs->{$_}->cas ] } keys %$lock_rvs
        );

        multi_ok($unlock_rvs, "unlock_multi");

    } else {
        diag "Skipping lock tests on mock";
    }

    $o->remove_multi(@keys);

    @set_args = map { [$_, { initial => 1 }] } @keys;
    multi_ok($o->incr_multi(@set_args), "incr_multi, key list with options");
    multi_ok($o->incr_multi(@keys), "incr_multi, key list");
    multi_ok($o->incr_multi($k1), "incr_multi. single key");
    multi_ok($o->incr_multi([$k1]), "incr_multi. single arrayref");
    multi_ok($o->incr_multi([$k1, { delta => 10 }]),
             "incr_multi. single arrayref with options");

    multi_ok($o->incr_multi_A(\@keys), "incr_multi_A - arrayref of keys");
    multi_ok($o->incr_multi_A([$k1]), "incr_multi_A, - single arrayref");
    multi_ok($o->incr_multi_A([[$k1]]), "incr_multi_A - single nested arrayref");

    multi_ok($o->remove_multi(@keys), "remove_multi - list of keys");
    multi_ok($o->remove_multi(@keys), "remove_multi - ENOENT", COUCHBASE_KEY_ENOENT);
    multi_ok($o->remove_multi_A(\@keys), "remove_multi_A", COUCHBASE_KEY_ENOENT);
}

sub T07_stats :Test(no_plan) {
    my $self = shift;
    my $o = $self->cbo;
    my $stats = $o->stats();

    ok($stats && ref $stats eq 'HASH', "Got a hashref");
    ok(scalar keys %$stats, "stats not empty");

    if($self->mock && $self->mock->nodes) {
        ok(scalar keys %$stats == $self->mock->nodes, "Got expected stat count");
    } else {
        diag "Cannot determine expected stat count for real cluster";
    }
}

sub T08_iterator :Test(no_plan) {
    my $self = shift;
    my $o = $self->cbo;
    my @keys = map { "T08_NonExistent_$_" } (1..200);
    my $iterator = $o->get_iterator_A(\@keys);
    ok(!$iterator->error, "Got no errors for creating iterator");

    my $rescount = 0;
    my $key_count = 0;
    my $not_found_count = 0;

    while (my ($k,$v) = $iterator->next) {
        if ($k) {
            $key_count++;
        }

        if ($v->KEY_ENOENT) {
            $not_found_count++;
        }
        $rescount++;
    }

    is($rescount, 200, "Got expected number of results");
    is($key_count, 200, "all keys received in good health");
    is($not_found_count, 200, "Got expected number of ENOENT");
}

sub T09_kwargs :Test(no_plan) {
    # Tests the keyword args functionality
    my $self = shift;
    my $o = $self->cbo;
    my $rv;

    $rv = $o->set("foo", "bar", { exp => 1 });
    ok($rv->is_ok);

    $rv = $o->set("foo", "bar", { cas => 0x4, exp => 43 });
    is($rv->errnum, COUCHBASE_KEY_EEXISTS);

    my $grv = $o->get("foo", {exp => 10 });
    $rv = $o->set("foo", "bar", { cas => $grv->cas});
    ok($rv->is_ok);

    # Try arithmetic
    $rv = $o->remove("arith_key");
    ok($rv->is_ok || $rv->errnum == COUCHBASE_KEY_ENOENT);

    $rv = $o->incr("arith_key", { initial => 40 });
    ok($rv->is_ok);
    is($rv->value, 40);
}

sub T10_locks :Test(no_plan) {
    my $self = shift;
    if ($self->mock && $self->mock->nodes) {
        diag "Skipping lock tests on mock";
        return;
    }

    my $lrv;
    my $o = $self->cbo;

    $lrv = $o->lock("foo", 10);
    ok($lrv->is_ok, "Lock OK");

    my $rv = $o->unlock("foo", $lrv->cas);
    ok($rv->is_ok, "Unlock OK");

    $rv = $o->unlock("foo", $lrv->cas);
    is($rv->errnum, COUCHBASE_ETMPFAIL, "Unlock with bad CAS: TMPFAIL");

    $lrv = $o->lock("foo", 10);
    my $fail_rv = $o->lock("foo", 10);
    is($fail_rv->errnum, COUCHBASE_ETMPFAIL, "Lock while locked. TMPFAIL");
    $fail_rv = $o->set("foo", "something");
    is($fail_rv->errnum, COUCHBASE_KEY_EEXISTS, "Storage fails with EEXISTS");

    $rv = $o->unlock("foo", $lrv->cas);
    ok($rv->is_ok, "Can unlock with valid CAS");
    $rv = $o->lock("foo", 10);
    ok($rv->is_ok, "Can lock again with valid CAS");
    $o->unlock("foo", $rv->cas);

    $rv = $o->unlock("foo", $rv->cas);
    is($rv->errnum, COUCHBASE_ETMPFAIL,
       "Unlock on unlocked key fails with ETMPFAIL");
}

sub wait_for_exp {
    my ($o,$k,$limit) = @_;
    my $begin_time = time();

    while (time() - $begin_time < $limit) {
        sleep(1);
        my $rv = $o->get($k);
        if ($rv->errnum == COUCHBASE_KEY_ENOENT) {
            return 1;
        }
        diag("Sleeping again..");
    }
    return 0;
}

sub T11_expiry :Test(no_plan) {
    my $self = shift;
    my $o = $self->cbo;
    $self->set_ok(
        "Setting with numeric expiry",
        "key", "value", 1);

    $self->set_ok(
        "Setting with stringified expiry",
        "key", "value", "1");


    eval {
        $o->set("key", "Value", "bad-expiry");
    };
    ok($@, "Got error for invalid expiry");

    # Hrm, this is apparently slower than i'd like. Let's use
    # a loop
    ok(wait_for_exp($o, "key", 3), "Key expired");

    # Try with multi
    eval {
        $o->set_multi(["key", "value", "blah"],
                      ["foo", "bar"])
    };
    ok($@, "Got error for invalid expiry (multi-set)");

    my $rvs = $o->set_multi(["key", "value", "1"],
                            ["foo", "bar"]);
    ok($rvs->{key}->is_ok, "Multi set with stringified expiry");
    ok(wait_for_exp($o, "key", 3), "Multi: Key expired");

}


1;
