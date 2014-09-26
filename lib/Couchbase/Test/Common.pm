package Couchbase::Test::Common;
use strict;
use warnings;
use base qw(Test::Class);
use Test::More;
use Couchbase::MockServer;
use Data::Dumper;
use Class::XSAccessor {
    accessors => [qw(mock res_buckets)]
};

our $Mock;
my $RealServer = $ENV{PLCB_TEST_SERVER};
my $RealPasswd = $ENV{PLCB_TEST_PASSWORD};

sub SKIP_CLASS {
    my ($cls,$msg) = @_;
    if(defined $msg) {
        my $cstr = ref $cls ? ref $cls : $cls;
        my $header = ("#" x 10) . " $cstr SKIP " . ("#" x 10);

        diag $header;
        diag "";
        diag $msg;
        diag "";
    }
    goto &Test::Class::SKIP_CLASS;
}

sub mock_init
{
    my $self = shift;
    if ( (!$Mock) && (!$RealServer) ) {
        die("Mock object not found. Initialize mock object with Initialize()");
    }
    $self->{mock} = $Mock;
}

sub fetch_config { }

use constant {
    BUCKET_MEMCACHED => 1,
    BUCKET_COUCHBASE => 2,
    BUCKET_DEFAULT => 3
};

sub common_options {
    my ($self,$bucket_type) = @_;

    if($RealServer) {
        return { %$RealServer };
    }
    my $mock = $self->mock;
    my $opthash = {};

    if(!$bucket_type) {
        $bucket_type = BUCKET_DEFAULT;
    } elsif ($bucket_type =~ /mem/) {
        $bucket_type = BUCKET_MEMCACHED;
    } elsif ($bucket_type =~ /couch/) {
        $bucket_type = BUCKET_COUCHBASE;
    } else {
        warn("No such bucket type $bucket_type");
        $bucket_type = BUCKET_DEFAULT;
    }

    my $bucket = $self->mock->buckets->[0] or die "No buckets!";
    if($bucket_type == BUCKET_MEMCACHED) {
        $bucket = (grep $_->{type} eq 'memcache',
                        @{$mock->buckets})[0];
    } elsif ($bucket == BUCKET_COUCHBASE) {
        $bucket = (grep { (!$_->{type}) || $_->{type} eq 'couchbase' }
                        @{$mock->buckets})[0];
    }
    if(!$bucket) {
        die("Can't find common options for bucket (@_)");
    }

    if($bucket->{password}) {
        $opthash->{password} = $bucket->{password};
    }
    $opthash->{connstr} = sprintf("http://localhost:%s/%s",
                                  $self->mock->port, $bucket->{name});
    print Dumper($opthash);
    return $opthash;
}

sub make_cbo {
    my $self = shift;
    my %options = %{ $self->common_options };
    $options{compress_threshold} = 100;
    return Couchbase::Client->new(\%options);
}

sub k2v {
    my ($self,$k) = @_;
    reverse($k);
}

sub v2k {
    my ($self,$v) = @_;
    reverse($v);
}

my $init_pid = $$;
sub Initialize {
    my ($cls,%opts) = @_;
    if($RealServer && (!ref $RealServer) ) {
        my $connstr = $RealServer;
        $RealServer = {
            connstr => $connstr,
            password => $RealPasswd
        };
    } else {
        eval {
            $Mock = Couchbase::MockServer->new(%opts);
        }; if( ($@ || (!$Mock)) && $$ == $init_pid) {
            $cls->SKIP_ALL("Cannot run tests without mock server ($@)");
        }
        return $Mock;
    }
}
1;
