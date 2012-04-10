package Couchbase::Couch::Design;
use strict;
use warnings;
use Couchbase::Client::IDXConst;
use base qw(Couchbase::Couch::HandleInfo);

sub view_path {
    my ($design_path,$view_name) = @_;
    return sprintf("%s/_view/%s", $design_path, $view_name);
}

sub get_view_path {
    my ($self,$view) = @_;
    my $v = ($self->value||{})->{views}->{$view};
    if ($v) {
        return view_path($self->path, $view);
    }
}

sub get_view_iterator {
    my ($self,$view,%options) = @_;
    my $vpath = $self->get_view_path($view) or die
        "no such view $view";
    $self->parent->couch_view_iterator($vpath,%options);
}

sub get_view_results {
    my ($self,$view,%options) = @_;
    my $vpath = $self->get_view_path($view);
    if (!$vpath) {
        die("No such view '$view'");
    }
    $self->parent->couch_view_slurp($vpath,%options);
}

1;


__END__

=head1 NAME

Couchbase::Couch::Design - Object representing a design document

=head1 DESCRIPTION

This manual page describes several convenience methods.

=head2 get_view_path($view_name)

Given the name of a view belonging to this design document, yields a path
appropriate for executing the view, e.g.

    my $design = $cbo->couch_design_get("a_design");
    my $vpath = $design->get_view_path("a_view");
    print $vpath;
    
    # => "_design/a_design/_view/a_view"
    
=head2 get_view_iterator($view_name,%options

Given a view name, get the L<Couchbase::Couch::Handle> object appropriate for it.

Equivalent to:

    $cbo->couch_view_iterator($design->get_view_path($view_name))

=head2 get_view_results($view_name,%options)

Equivalent to:

    $cbo->couch_view_slurp($design->get_view_path($view_name));