package Couchbase::View::Row;
use strict;
use warnings;
use Class::XSAccessor accessors => [qw(key value id)];

package Couchbase::View::Handle;
##
# This is mainly an (abstract) base class for all handle objects.
use strict;
use warnings;
use Couchbase;
use Couchbase::_GlueConstants;
use Carp qw(cluck);
use base qw(Couchbase::View);

# This does some boilerplate initialization, ensuring that our private
# fields are initialized. Subclasses usually override this method and end up
# calling this via SUPER
sub _perl_initialize {
    my $self = shift;
    $self->info->_priv([]);

    # These two statements declare the callbacks.
    # The CALLBACK_DATA and CALLBACK_COMPLETE correspond to the handlers which
    # will be invoked by libcouchbase for the respective events.
    # These callbacks should warn.

    $self->info->[COUCHIDX_CALLBACK_DATA] = \&default_data_callback;
    $self->info->[COUCHIDX_CALLBACK_COMPLETE] = \&default_complete_callback;
    return $self;
}

# Convenience function
sub path { shift->info->path }

sub default_data_callback {
    cluck "Got unhandled data callback";
    print Dumper($_[1]);
}

sub default_complete_callback {
    print Dumper($_[1]);
    cluck "Got unhandled completion callback..";
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

