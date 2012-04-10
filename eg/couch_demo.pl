#!/usr/bin/perl
# This feature demonstrates several aspects of dealing with Couch using the
# Perl API

use strict;
use warnings;
use blib;
use Couchbase::Client;
use Couchbase::Client::IDXConst;
use Data::Dumper::Concise;
use JSON::XS;
use Log::Fu;
use Carp qw(confess);
$SIG{__DIE__} = \&confess;

# Create the client
my $cbo = Couchbase::Client->new({
        username=> "Administrator",
        password=> "123456",
        bucket => "membase0",
        server => "10.0.0.99:8091"
});

# Create some sample data to work with
my @posts = (
    [ "bought-a-cat" => {
            title => "bought-a-cat",
            body => "I went to the pet store earlier and brought home a little kitty",
            date => "2009/01/30 18:04:11"
        }],
    [ "biking" => {
            title => "Biking",
            body => "My biggest hobby is mountainbiking. The other day...",
            date => "2009/01/30 18:04:11"
        }],
    [ "hello-world" => {
            title => "Hello World",
            body => "Well hello and welcome to my new blog...",
            date => "2009/01/15 15:52:20"
        }]
);

foreach (0..100) {
    my $k = "Post_$_";
    push @posts, [$k, {
                       title => "Title_$k",
                       body => "Body_$k",
                       date => "2012/03/23 13:53:00",
                       counter => rand(30000)
                }];
}

# store all the posts, while checking for errors
{
    my $results = $cbo->couch_set_multi(@posts);
    my @errkeys = grep { !$results->{$_}->is_ok } keys %$results;
    if (@errkeys) {
        die ("Store did not succeed! Errored keys: ".join(",", @errkeys));
    }
}


#create a design doc
{
    my $design_json = {
        _id => "_design/blog",
        language => "javascript",
        views => {
            recent_posts => {
               "map" => 'function(doc) '.
               '{ if(doc.date&&doc.title)' .
              ' { emit(doc.date,doc.title); } }'
            }
        }
    };
    #my $retval = $cbo->couch_design_put($design_json);
    #log_infof("Path=%s, Return HTTP=%d, (Ok=%d)",
    #          $retval->path, $retval->http_code, $retval->is_ok);
    #if (!$retval->is_ok) {
    #    log_errf("Couldn't save design doc: %s", Dumper($retval->value));
    #}
}

# Get the design document again..
my $Design;
{
    # re-get our design document, to make sure it still exists..
    $Design = $cbo->couch_design_get("blog");
    log_infof("Got design. Path=%s, HTTP=%d (Ok=%d)",
        $Design->path, $Design->http_code, $Design->is_ok);

}


# let's get the path for the view. this is nice if we intend to perform lower
# level operations

my $view = $Design->get_view_path("recent_posts");
log_info("View path is $view");


# fetch all the results at once. Might be memory-hungry!
{
    my $resultset = $Design->get_view_results("recent_posts");
    if (!$resultset->is_ok) {
        die "Got resultset error: ". $resultset->errstr;
    }
    eval {
        log_infof("Got %d rows", scalar @{$resultset->rows} );
    }; if ($@) {
        print Dumper($resultset);
        die $@;
    }
}

# We can be more efficient by using an iterator to incrementally fetch the results
{
    $|= 1;
    my $iter = $Design->get_view_iterator("recent_posts",
                                          ForUpdate => 1,
                                          limit => 10);
    
    log_infof("Have iterator. Path: %s", $iter->path);
    my $rescount = 0;
    while (my $row = $iter->next) {
        $rescount++;
        # Display our progress
        print "+";
            
        # Get the old value. We compare this later
        my $old_val = $row->doc->{counter} || 0;
        
        # Increment the value:
        $row->doc->{counter} += 20;
        $row->save();

        my $new_row = $cbo->couch_doc_get($row->id);
        
        if ($new_row->value->{counter} != $old_val+20) {
            die("Didn't get expected updates...");
        }
        print " " . $new_row->value->{counter} . " ";
    }
    print "\n";
    
    log_infof("Got a total of %d/%d rows", $rescount, $iter->count);
    
    log_infof("Error string (if any) %s", $iter->info->errstr || "<NO ERROR>");
}
