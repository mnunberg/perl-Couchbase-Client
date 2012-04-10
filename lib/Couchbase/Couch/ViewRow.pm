package Couchbase::Couch::ViewRow;
use strict;
use warnings;
use Class::XSAccessor {
    accessors => [ qw(key value id doc _cbo) ]
};

sub save {
    my ($self,%options) = @_;
    my $cbo = $self->{_cbo} || delete $options{Client};
    if (!$cbo) {
        die("Must have client (Either implicit or explicit)");
    }
    if (!$self->{doc}) {
        die("View result does not include doc");
    }
    return $cbo->couch_set($self->{id}, $self->doc);
}

1;

__END__

=head1 NAME

Couchbase::Couch::ViewRow - Object representing a single view from a resultset

=head1 DESCRIPTION

This object has several accessors which just get and set the approrpiate values:


=head2 key

The key emitted by the map-reduce function

=head2 value

The value for L</key>

=head2 id

The id of the document from which the key and value were derived

=head2 doc

The full document. This is only valid for queries where C<include_docs=true>, or
where C<ForUpdate> was specified in the view execution.

=head2 save(%options)

Saves the document back to couchbase. Options are as follows

=over

=item Client

This is a L<Couchbase::Client> object. Currently this field is not needed
because the client is attached to this object during its creation

=back

Returns a L<Couchbase::Client::Return> indicating the status of the operation.

