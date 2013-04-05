package Couchbase::Test::Views;
use strict;
use warnings;
use base qw(Couchbase::Test::Common);
use Test::More;
use Couchbase::Client;
use Couchbase::Client::Errors;
use Data::Dumper;
use Class::XSAccessor {
    accessors => [ qw(cbo) ]
};

use constant {
    DESIGN_NAME => "blog"
};

my $DESIGN_JSON = {
    _id => "_design/blog",
    language => "javascript",
    views => {
        recent_posts => {
            map => 'function(doc) ' .
            '{ if (doc.date && doc.title) ' .
            '{ emit(doc.date, doc.title); } }'
        }
    }
};

sub SKIP_CLASS {

    if (!$Couchbase::Test::Common::RealServer) {
        return 1;
    }

    return 0;
}

sub setup_client :Test(startup) {
    my $self = shift;
    $self->cbo( $self->make_cbo );
}

sub TV01_create_ddoc :Test(no_plan) {

    my $self = shift;
    my $o = $self->cbo;
    my $ret = $o->couch_design_put($DESIGN_JSON);
    ok($ret->is_ok, "Design doc put did not return errors");

    my $design = $o->couch_design_get(DESIGN_NAME);

    isa_ok($design, 'Couchbase::Couch::Design');
    is($design->path, '_design/blog', "Have path");
    is($design->http_code, 200, "Have HTTP 200");
    ok($design->is_ok, "Overall object OK");
    is_deeply($design->value, $DESIGN_JSON, "Got back view");
}

sub TV02_create_invalid_ddoc :Test(no_plan) {
    my $self = shift;
    my $o = $self->cbo;

    eval {
        $o->couch_design_put("blah");
    }; like($@, '/path cannot be empty/');

    my $ret = $o->couch_design_put({
        _id => "_design/meh",
        views => {
            foo => "blehblehbleh"
        }
    });

    is($ret->http_code, 400, "Got error for invalid view");
    is($ret->errinfo->{error}, "invalid_design_document");
}

sub TV03_view_query :Test(no_plan) {
    my $self = shift;
    my $o = $self->cbo;

    # First, load up the keys
    my @posts = (
        [ "bought-a-cat" => {
            title => "bought-a-cat",
            body => "I went to the pet store earlier and brought home a little kitty",
            date => "2009/01/30 18:04:11"
        }],
        [ "biking" => {
            title => "Biking",
            body => "My biggest hobby is mountainbiking. The other day..",
            date => "2009/01/30 18:04:11"
        }],
        [ "hello-world" => {
            title => "Hello World",
            body => "Well hello and welcome to my new blog...",
            date => "2009/01/15 15:52:20"
        }]
    );

    my %dkeys = map { $_->[0], 1 } @posts;

    # See if we can slurp the view
    my $res = $o->couch_view_slurp(["blog", "recent_posts"], stale => "false");

    my @rm_errors = ();
    foreach my $id (map $_->{id}, @{ $res->value }) {
        my $rv = $o->remove($id);
        if (!$rv->is_ok) {
            push @rm_errors, $rv;
        }
    }

    ok(!@rm_errors);

    my $results = $o->couch_set_multi(@posts);
    my @errkeys = grep { !$results->{$_}->is_ok } keys %$results;
    ok(!@errkeys, "No store errors");
    $res = $o->couch_view_slurp(["blog", "recent_posts"],
                                stale => "false");
    isa_ok($res, 'Couchbase::Couch::HandleInfo');

    my %rkeys = map { $_->{id}, 1 } @{ $res->value };
    is_deeply(\%rkeys, \%dkeys, "Got back the same rows");

    %rkeys = ();
    # Try with the view iterator
    my $iter = $o->couch_view_iterator(["blog", "recent_posts"]);
    my $rescount = 0;
    while (my $row = $iter->next) {
        $rescount++;
        $rkeys{$row->id} = 1;
    }

    is_deeply(\%rkeys, \%dkeys, "View Iterator");
}

sub TV04_vq_errors :Test(no_plan) {
    my $self = shift;
    my $o = $self->cbo;

    my $res = $o->couch_view_slurp(["nonexist", "nonexist"]);
    isa_ok($res, 'Couchbase::Couch::HandleInfo');
    ok(!$res->is_ok);
    is($res->http_code, 404);

    my $path_re = '/path/i';

    eval {
        $res = $o->couch_view_slurp();
    }; like($@, $path_re);

    eval {
        $res = $o->couch_view_slurp([]);
    }; like($@, $path_re);

    eval {
        $res = $o->couch_view_slurp([undef, undef]);
    }; like($@, $path_re);

    # Test with invalid view parameters
    $res = $o->couch_view_slurp(["blog", "recent_posts"],
                                 'include_docs' => 'bad ^VALUE^');
    is($res->http_code, 400);
}

sub TV05_empty_rows :Test(no_plan) {
    my $self = shift;
    my $o = $self->cbo;
    my $res = $o->couch_view_slurp(['blog', 'recent_posts'],
                                   limit => 0);
    is_deeply($res->value, [], "No rows");


    $res = $o->couch_view_iterator(['blog', 'recent_posts'],
                                   limit => 0);

    ok(!$res->next);
    is($res->info->http_code, 200);
}

sub TV06_iterator :Test(no_plan) {
    my $self = shift;

    my $iter;
    {
        my $o = $self->make_cbo();
        $iter = $o->couch_view_iterator(['blog', 'recent_posts']);
    }
    ok($iter->next, "Iterator keeps object in scope");

    $iter->stop();
    ok($iter->count, "Can get count");


    # Create a rather long view/design document, so that
    # we can guarantee to get a split buffer.

    my $mapfn = <<EOF;
function (doc) {
    if (doc.tv06_iterator) {
        emit(doc.tv06_iterator);
    }
}
EOF

    my $d_json = {
        _id => '_design/tv06',
        language => 'javascript',
        views => {
            tv06 => {
                map => $mapfn
            }
        }
    };

    my $o = $self->cbo;
    my $rv = $o->couch_design_put($d_json);
    ok($rv->is_ok);

    my @objs = ();
    foreach my $i (0..2000) {
        my $kv = ['key-tv06-'.$i, {'tv06_iterator' => $i}];
        push @objs, $kv;
    }
    my $rvs = $o->couch_set_multi(@objs);

    # Make sure there are no store errors
    my @errs = grep { !$rvs->{$_}->is_ok } keys %$rvs;
    ok(!@errs, "No store errors");

    # Now, query the view
    $iter = $o->couch_view_iterator(['tv06', 'tv06'],
                                    stale => 'false', limit => '100');
    # Do we have a count?

    my %rkeys;
    my @kv_errors = ();
    my @rows;
    do {
        @rows = $iter->next;
        my $krv = $o->set("foo", "bar");
        if (!$krv->is_ok) {
            push @kv_errors, $krv;
        }
    } while (@rows);

    ok(!@kv_errors, "No errors during async handle usage");
}

1;
