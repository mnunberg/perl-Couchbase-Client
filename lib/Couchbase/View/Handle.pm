package Couchbase::View::Row;
use strict;
use warnings;
use Class::XSAccessor accessors => [qw(key value id geometry)];

package Couchbase::View::Handle;
use strict;
use warnings;
use Couchbase;
use Couchbase::_GlueConstants;
use URI::Escape qw(uri_escape);
use Carp qw(cluck);
use JSON;
use base (qw(Couchbase::Document));
use Constant::Generate [qw(ERRINFO ROWCOUNT REQFLAGS)], start_at => 0;
use Devel::Peek;

use Class::XSAccessor::Array accessors => {
    _priv => VHIDX_PLPRIV,
    done => VHIDX_ISDONE,
    rows => VHIDX_ROWBUF,
    meta => VHIDX_META,
    http_code => VHIDX_HTCODE
};

my $JSON = JSON->new->allow_nonref;

sub new {
    my ($cls, $parent, $viewspec, %options) = @_;
    my ($view, $design) = ($viewspec =~ m,([^/]+)/(.*),);
    die("Must pass view/design") unless $view && $design;

    my $flags;
    if (delete $options{spatial}) {
        $flags |= LCB_CMDVIEWQUERY_F_SPATIAL;
    }
    if (delete $options{include_docs}) {
        $flags |= LCB_CMDVIEWQUERY_F_INCLUDE_DOCS;
    } else {
        $flags |= LCB_CMDVIEWQUERY_F_NOROWPARSE;
    }



    # Form the options string
    my $opt_str = join('&', map {
        sprintf("%s=%s", uri_escape($_), uri_escape($options{$_}))
    } keys %options);


    my $inner = Couchbase::_viewhandle_new($parent, $view, $design, $opt_str, $flags);

    $inner->[VHIDX_PRIVCB] = \&row_callback;
    $inner->[VHIDX_PLPRIV] = [];
    $inner->[VHIDX_PATH] = $viewspec;
    $inner->_priv->[REQFLAGS] = $flags;

    return $inner;
}

sub row_callback {
    my ($self, $rows) = @_;
    if (!$rows) {
        $self->process_meta();
        return;
    }

    # It's significantly quicker if we can reduce the number of subcalls to the JSON
    # parser.
    my $parse_whole =
        $self->[VHIDX_PLPRIV]->[REQFLAGS] & LCB_CMDVIEWQUERY_F_NOROWPARSE;

    foreach my $row (@$rows) {
        if ($parse_whole) {
            $row = $JSON->decode($row->{value});
        } else {
            foreach my $k (qw(key value geometry)) {
                if ((my $tmp = $row->{$k})) {
                    $row->{$k} = $JSON->decode($tmp);
                }
            }
        }

        bless $row, 'Couchbase::View::Row';
        push @{$self->rows}, $row;
    }
}

sub is_ok {
    my $self = shift;
    if (!$self->SUPER::is_ok()) {
        return 0;
    }
    if ($self->errinfo) {
        return 0;
    }
    return 1;
}

sub path {
    return shift->id;
}

sub cas {
    warn ("This method is not implemented for " . __PACKAGE__);
    return;
}

sub count {
    return shift->_priv->[ROWCOUNT];
}

sub errinfo {
    my $self = shift;
    return $self->_priv->[ERRINFO];
}

sub errstr {
    my $self = shift;
    my $ret = $self->SUPER::errstr;
    if (!$ret) {
        return $ret;
    }
    if ($self->http_code !~ /^2\d\d/) {
        $ret .= sprintf(" (HTTP=%d)", $self->http_code);
    }
    if ($self->errinfo) {
        if (ref $self->errinfo eq 'ARRAY') {
            $ret .= " [There were some errors fetching individual rows. See ->errinfo]";
        } elsif (ref $self->errinfo eq 'HASH') {
            $ret .= sprintf(" [Query Error (error=%s, reason=%s)]",
                            $self->errinfo->{error}, $self->errinfo->{reason});
        }
    }
    return $ret;
}

sub next {
    my $self = shift;

    GT_AGAIN:
    if (!@{$self->rows}) {
        if ($self->done) {
            return undef;
        }
        Couchbase::_viewhandle_fetch($self);
        goto GT_AGAIN;
    }

    return shift @{$self->rows};
}

sub slurp {
    my $self = shift;
    while (!$self->done) {
        Couchbase::_viewhandle_fetch($self);
    }
    return $self->rows;
}

sub process_meta {
    my $self = shift;
    my $meta = $self->[VHIDX_META];

    if (!defined($meta)) {
        return; # oops
    }

    my $json;
    eval {
        $json = $JSON->decode($meta);
    };

    if (!$json) {
        return; # Not JSON!
    }

    if (exists $json->{errors}) {
        # Errors received from individual nodes
        $self->_priv->[ERRINFO] = delete $json->{errors};
    } elsif (exists $json->{error}) {
        # Errors received for the query itself, e.g. "not_found"
        $self->_priv->[ERRINFO] = {
            reason => delete $json->{reason},
            error => delete $json->{error}
        };
    }
    $self->_priv->[ROWCOUNT] = $json->{total_rows};
}

sub as_hash {
    my $self = shift;
    my %h = (
        path => $self->path,
        count => $self->count,
        status => $self->errstr,
    );
    if (!$self->is_ok) {
        $h{errinfo} = $self->errinfo;
    }
    return \%h;
}

1;

__END__

=head1 NAME


Couchbase::View::Handle - Class for view query handles


=head1 DESCRIPTION

This class represents a common inteface for various request handles.
Emphasis will be placed on the iterating view handle, since this is the most common
use case (technical and more 'correct' documentation will follow).

The iterator is simple to use. Simply initialize it (which is done for you
automatically by one of the L<Couchbase::View::Base> methods which return this
object) and step through it. When there are no more results through which to
step, the iterator is empty.

Note that iterator objects are fully re-entrant and fully compatible with the
normal L<Couchbase::Client> blocking API. This means that multiple iterators are
allowed, and that you may perform modifications on the items being iterated
upon.

