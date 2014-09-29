package Couchbase;
our $VERSION = '2.0.0_1';
1;

BEGIN {
    require XSLoader;
    our $VERSION = '2.0.0_1';
    XSLoader::load('Couchbase', $VERSION);
}

use Couchbase::_GlueConstants;
use Couchbase::Bucket;

our @ERRMAP = ();

package Couchbase::Cluster;
use strict;
use warnings;
use URI;

sub q2hash($) {
    my $s = shift || '';
    my %rv = ();
    foreach my $pair (split('&', $s)) {
        my ($k,$v) = split('=', $pair);
        $rv{$k} = $v;
    }
    return \%rv;
}

sub parse_connstr($) {
    # Parses a connection string into its constituent parts
    my $uri = URI->new(shift);
    my %h = ();

    $h{scheme} = $uri->scheme;
    $h{hosts} = [ split(/,/, $uri->authority) ];
    $h{options} = q2hash($uri->query);
    $h{bucket} = $uri->path;
    $h{bucket} =~ s,^/+,,g;
    return \%h;
}

sub new {
    my ($pkg,$connstr) = @_;
    bless my $self = {
        connstr => parse_connstr($connstr),
        buckets => {}
    }, $pkg;
}

sub open_bucket {
    my ($self, $bucket_spec, $options) = @_;
    # Inject the URI into the connection string, merging them
    $bucket_spec = sprintf("%s://XXX/%s", $self->{connstr}->{scheme}, $bucket_spec);
    my $b_cstr = parse_connstr($bucket_spec);

    # Build the URI
    my $s = sprintf("%s://%s/%s?",
                    $self->{connstr}->{scheme},
                    join(',', @{ $self->{connstr}->{hosts} }),
                    $b_cstr->{bucket});


    # Now, merge the options:
    my %h = ( %{$self->{connstr}->{options} } );
    # Allow any overrides:
    %h = (%h, % { $b_cstr->{options} });
    my @tmp;
    while (my ($k,$v) = each %h) {
        push @tmp, "$k=$v";
    }
    $s .= join('&', @tmp);
    if ($self->{buckets}->{$s}) {
        return $self->{buckets}->{$s};
    } else {
        return $self->{buckets}->{$s} = Couchbase::Bucket->new($s, $options);
    }
}

1;

__END__

=head1 NAME

Couchbase - Perl client for L<Couchbase|http://www.couchbase.com>

This is the Couchbase client for Perl. It replaces the older L<Couchbase::Client>.

It depends on L<libcouchbases|http://couchbase.com/communities/c>.


=head2 SYNOPSIS


    use Couchbase;
    my $cluster = Couchbase::Cluster->new("couchbase://host1,host2,host3");
    my $bkt_defl = $cluster->open_bucket("default");
    my $bkt_beer = $cluster->open_bucket("beer-sample");
    my $bkt_other = $cluster->open("other_bucket?config_cache=/foo/bar/baz.cache");


=head2 DESCRIPTION


The C<Couchbase::Cluster> class represents a top level object which can be used
to store common connection settings about an L<Couchbase::Bucket>.


=head3 CONSTRUCTOR

The constructor accepts a URI-like format (see the constructor for
L<Couchbase::Bucket>), but I<without> the bucket name itself being specified.


=head2 open_bucket

This returns a connected bucket based on the bucket name. The bucket name
itself may be followed by a C<?> and several I<options>, (like the
connection string itself).


If an open bucket already exists with the given connection string, that bucket
is returned rather than opening a new one.



=head1 SEE ALSO


L<Couchbase::Bucket> - Main bucket class.
