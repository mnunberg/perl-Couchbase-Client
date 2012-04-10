#!/usr/bin/perl
use strict;
use warnings;
use blib;
use Couchbase::Client;
use Log::Fu;
use Data::Dumper;
use Time::HiRes qw(time sleep);

my $cbo = Couchbase::Client->new({
        username => "Administrator",
        password => "123456",
        bucket => "membase0",
        server => "10.0.0.99:8091"
});

my @Keys = map { "IterKey$_" } (0..20);

# Store the key. $results is the results of the store operation
my $results = $cbo->set_multi(  map { [ $_, scalar reverse($_) ] } @Keys );


# set the timeout, so we can demonstrate!
my $Begin = time();
$cbo->timeout(60); # 60 seconds

# get_iterator creates a new iterator object
my $iterator = $cbo->get_iterator(@Keys);
my $iterator2 = $cbo->get_iterator(@Keys);

printf("Starting Query..\n");

# Continue fetching the 'next' result. ->next returns nothing
# once there are no more results
while (my ($key,$ret) = $iterator->next) {
    printf("Elapsed: %d, Got return for %s (Value=%s)\n",
        time() - $Begin, $key, $ret->value);
    sleep(1.5);
    ($key,$ret) = $iterator2->next();
    printf("Got result for key %s from second iterator\n", $key);
}

printf("All values done. Waited %d secs\n", time() - $Begin);

__END__

Starting Query..
Elapsed: 0, Got return for IterKey0 (Value=0yeKretI)
Elapsed: 1, Got return for IterKey19 (Value=91yeKretI)
Elapsed: 3, Got return for IterKey16 (Value=61yeKretI)
Elapsed: 4, Got return for IterKey15 (Value=51yeKretI)
Elapsed: 6, Got return for IterKey13 (Value=31yeKretI)
Elapsed: 7, Got return for IterKey10 (Value=01yeKretI)
Elapsed: 9, Got return for IterKey9 (Value=9yeKretI)
Elapsed: 10, Got return for IterKey6 (Value=6yeKretI)
Elapsed: 12, Got return for IterKey5 (Value=5yeKretI)
Elapsed: 13, Got return for IterKey3 (Value=3yeKretI)
Elapsed: 15, Got return for IterKey20 (Value=02yeKretI)
Elapsed: 16, Got return for IterKey18 (Value=81yeKretI)
Elapsed: 18, Got return for IterKey17 (Value=71yeKretI)
Elapsed: 19, Got return for IterKey14 (Value=41yeKretI)
Elapsed: 21, Got return for IterKey12 (Value=21yeKretI)
Elapsed: 22, Got return for IterKey11 (Value=11yeKretI)
Elapsed: 24, Got return for IterKey8 (Value=8yeKretI)
Elapsed: 25, Got return for IterKey7 (Value=7yeKretI)
Elapsed: 27, Got return for IterKey4 (Value=4yeKretI)
Elapsed: 28, Got return for IterKey2 (Value=2yeKretI)
Elapsed: 30, Got return for IterKey1 (Value=1yeKretI)
All values done. Waited 31 secs

