package Couchbase::Client::Compat;
use strict;
use warnings;
use base qw(Couchbase::Client);
use Couchbase::Client::Errors;

sub new {
    my ($cls,$options) = @_;
    my $o = $cls->SUPER::new($options);
}

sub get {
    my $self = shift;
    $self->SUPER::get(@_)->value(@_);
}

sub gets {
    my $self = shift;
    my $ret = $self->SUPER::get(@_);
    if($ret->is_ok) {
        return [ $ret->cas, $ret->value ];
    } else {
        return undef;
    }
}


foreach my $sub qw(set add replace append prepend cas) {
    no strict 'refs';
    *{$sub} = sub {
        my $self = shift;
        my $ret = $self->${\"SUPER::$sub"}(@_);
        if($ret->is_ok) {
            return 1;
        } elsif ($ret->errnum == COUCHBASE_NOT_STORED ||
                 $ret->errnum == COUCHBASE_KEY_EEXISTS ||
                 $ret->errnum == COUCHBASE_KEY_ENOENT) {
            return 0;
        } else {
            return undef;
        }
    };   
}

__END__

=head1 NAME

Couchbase::Client::Compat - Cache::Memcached::-compatible interface

=head1 DESCRIPTION

This subclasses and wraps L<Couchbase::Client> to provide backwards-compatibility
with older code using L<Cache::Memcached> or L<Cache::Memcached::Fast>. See either
of those pages for documentation of the methods supported.

=head2 SUPPORTED METHODS

=over

=item get

=item gets

=item set

=item cas

=item add

=item replace

=item append

=item prepend

=back

=head2 SEE ALSO

L<Cache::Memcached>

L<Cache::Memcached::Fast>

L<Cache::Memcached::libmemcached>


=head1 AUTHOR & COPYRIGHT

Copyright (C) 2012 M. Nunberg

You may use and distribute this software under the same terms, licensing, and
conditions as perl itself.