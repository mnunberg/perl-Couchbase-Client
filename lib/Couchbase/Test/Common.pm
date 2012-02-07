package Couchbase::Test::Common;
use strict;
use warnings;
use base qw(Test::Class);
use Test::More;
use Couchbase::MockServer;
use Data::Dumper;

our $Mock;
our $RealServer = $ENV{PLCB_TEST_REAL_SERVER};
our $MemdPort = $ENV{PLCB_TEST_MEMD_PORT};
sub mock_init
{
    my $self = shift;
    if(!$Mock) {
        die("Mock object not found. Initialize mock object with Initialize()");
    }
    $self->{mock} = $Mock;
}

sub mock { $_[0]->{mock} }

sub common_options {
    my $self = shift;
    
    if($RealServer) {
        return { %$RealServer };
    }
    
    my $opthash = {};
    my $defbucket = $self->mock->buckets->[0];
    
    if($defbucket->{password}) {
        $opthash->{username} = "some_user";
        $opthash->{password} = $defbucket->{password};
    }
    $opthash->{server} = "127.0.0.1:" . $self->mock->port;
    $opthash->{bucket} = $defbucket->{name};
    return $opthash;
}

sub memd_options {
    if(!$MemdPort) {
        die("Cannot find Memcached port");
    }
    my ($hostname) = split(/:/, $RealServer->{server});
    $hostname .= ":$MemdPort";
    return {
        servers => [ $hostname ]
    };
}

sub k2v {
    my ($self,$k) = @_;
    reverse($k);
}

sub v2k {
    my ($self,$v) = @_;
    reverse($v);
}

sub Initialize {
    my ($cls,%opts) = @_;
    if($RealServer && (!ref $RealServer) ) {
        warn("Using real server..");
        my @kvpairs = split(/,/, $RealServer);
        $RealServer = {};
        foreach my $pair (@kvpairs) {
            my ($k,$v) = split(/=/, $pair);
            $RealServer->{$k} = $v if $k =~ /server|bucket|username|password|memd_port/;
        }
        $RealServer->{server} ||= "localhost:8091";
        $RealServer->{bucket} ||= "default";
        $MemdPort ||= delete $RealServer->{memd_port};
        $Mock = 1;
    } else {
        $Mock = Couchbase::MockServer->new(%opts);
        return $Mock;
    }
}
1;