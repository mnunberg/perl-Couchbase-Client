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
    $self->parent->couch_view_iterator($vpath);
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
