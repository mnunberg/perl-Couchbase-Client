package Couchbase::View::HandleInfo;

use strict;
use warnings;

use Couchbase::Document;
use Couchbase::_GlueConstants;
use JSON;
use base qw(Couchbase::Document);

use Class::XSAccessor::Array {
    accessors => {
        http_code => COUCHIDX_HTTP,
        on_data => COUCHIDX_CALLBACK_DATA,
        on_complete => COUCHIDX_CALLBACK_COMPLETE,
        path => COUCHIDX_PATH,
        parent => COUCHIDX_CBO,
        errinfo => COUCHIDX_ERREXTRA,
        count => COUCHIDX_ROWCOUNT,
        _priv => COUCHIDX_UDATA
    }
};

sub cas {
    warn ("This method is not implemented for " . __PACKAGE__);
    return;
}


# These two methods implement handling of HTTP errors as well
sub is_ok {
    my $self = shift;
    my $ret = $self->SUPER::is_ok();
    if (!$ret) {
        return $ret;
    }
    if ($self->errinfo) {
        return 0;
    }
    if ($self->http_code > 299 && $self->http_code < 200) {
        return 0;
    }
    return $ret;
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

sub _extract_row_errors {
    my ($self,$hash) = @_;
    if (exists $hash->{errors}) {
        # Errors received from individual nodes
        $self->[COUCHIDX_ERREXTRA] = delete $hash->{errors};
    } elsif (exists $hash->{error}) {
        # Errors received for the query itself, e.g. "not_found"
        $self->[COUCHIDX_ERREXTRA] = {
            reason => delete $hash->{reason},
            error => delete $hash->{error}
        };
    }
}

sub _extract_item_count {
    my ($self,$hash) = @_;
    if (!defined $hash) {
        return;
    }

    $self->[COUCHIDX_ROWCOUNT] = $hash->{total_rows};
    return $self->[COUCHIDX_ROWCOUNT];
}

sub _extract_view_results {
    my $self = shift;
    my $json = delete $self->[RETIDX_VALUE];
    if (defined $json) {
        $json = decode_json($json);
        $self->_extract_row_errors($json);
        $self->[RETIDX_VALUE] = delete $json->{rows};
    }
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

{
    no warnings 'once';
    *rows = *Couchbase::Document::value;
}

1;

__END__

=head1 NAME

Couchbase::View::HandleInfo - informational subclass of Couchbase::Document

=head1 DESCRIPTION

This object subclasses L<Couchbase::Document> and fulfills the same role (
but for couchbase view requests, rather than memcached operations).

=head2 ADDED FIELDS

These fields are added to the L<Couchbase::Document> object

=head3 http_code

Returns the HTTP status code for the operation, e.g C<200> or C<404>

=head3 path

Returns the HTTP URI for this operation

=head3 count

Returns the count (if any) for the matched result

=head3 errinfo

Returns extended (non-http, non-libcouchbase, non-memcached) error information.
This is usually a hash converted from a JSON error response.


=head2 REIMPLEMENTED FIELDS

The following fields behave differently in this subclass

=head3 is_ok

=head3 errstr

In addition to checking the libcouchbase and memcached error codes, also checks
the HTTP codes and the JSON-level server errors
