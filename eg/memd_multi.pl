package CouchMulti;
use strict;
use warnings;
use blib;
use base qw(Couchbase::Client);
use Data::Dumper;

use Log::Fu { level => "debug" };

sub runloop {
    my $o = shift;
    my @klist = qw(Foo Bar Baz Blargh Bleh Meh Grr Gah);
    my $params = [ map { [$_, uc("$_")] } @klist ];

    my $res = $o->set_multi($params);

    log_infof("Have missing results: %d",
        scalar grep {!exists $res->{$_} } @klist);

    log_infof("Have failed results: %s",
        join(",", grep { !$res->{$_}->is_ok } @klist) || "NONE");

    log_info("SET OK");

    foreach my $k (@klist) {
        my $ret = $o->get($k);
        unless($ret->is_ok && defined $ret->value) {
            log_errf("Couldn't get (single) for key %s", $k);
        }
    }
    log_info("All keys single-get OK");
    log_info("Calling GET_MULTI");
    $res = $o->get_multi(@klist, 'blarh', 'sfsadf', 'enoent', 'ZZOOOOff');
    log_info("GET Done");
    log_infof("Unexpected results: %s",
        join(",", grep { $res->{$_}->value ne uc($_) } @klist) || "NONE");

    
    my $old_res = $res;

    $res = $o->cas_multi(map {
        [$_, uc($_), $res->{$_}->cas ]
        } @klist);

    log_infof("Have failed: %d",
        scalar grep {!$res->{$_}->is_ok} @klist);

}

my $o = __PACKAGE__->new({
        server => '10.0.0.99:8091',
        username => 'Administrator',
        password => '123456',
        bucket => 'membase0',
        compress_threshold => 100,
    });
bless $o, __PACKAGE__;
my $LOOPS = shift @ARGV;
if($LOOPS) {
    $Log::Fu::SHUSH = 1;
    $o->runloop() for (0..$LOOPS);
} else {
    $o->runloop();
}
