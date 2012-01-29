package Couchbase::Test::Common;
use strict;
use warnings;
use base qw(Test::Class);
use Test::More;
use Couchbase::MockServer;
use Data::Dumper;

our $Mock;

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
    $Mock = Couchbase::MockServer->new(%opts);
    return $Mock;
}
1;