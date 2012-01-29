package Couchbase::MockServer;
use strict;
use warnings;
use LWP::UserAgent;
use File::Basename;
use URI;
use File::Path qw(mkpath);
use IO::Socket::INET;
use Socket;
use POSIX qw(:errno_h :signal_h);
use Time::HiRes;
use Log::Fu;
use Data::Dumper;



my $SYMLINK = "CouchbaseMock_PLTEST.jar";
our $INSTANCE;

use Class::XSAccessor {
    constructor => '_real_new',
    accessors => [qw(
        harakiri_addr
        port
        pid
        dir
        url
        nodes
        buckets
        vbuckets
        harakiri_socket
    )]
};
# This is the couchbase mock server, it will attempt to download, spawn, and
# otherwise control the java-based CouchbaseMock server.

sub _do_run {
    my $self = shift;
    my @command;
    push @command, "java", "-jar", $self->dir . "/$SYMLINK";
    
    my $buckets_arg = "--buckets=";
    
    foreach my $bucket (@{$self->buckets}) {
        my ($name,$password,$type) = @{$bucket}{qw(name password type)};
        $name ||= "";
        $password ||= "";
        $type ||= "";
        if($type && $type ne "couchbase" && $type ne "memcache") {
            die("type for bucket must be either 'couchbase' or 'memcache'");
        }
        my $spec = join(":", $name, $password, $type);
        $buckets_arg .= $spec . ",";
    }
    
    $buckets_arg =~ s/,$//g;
    
    push @command, $buckets_arg;
    
    push @command, "--port=" . $self->port;
    
    if($self->nodes) {
        push @command, "--nodes=" . $self->nodes;
    }
    
    if($self->harakiri_addr) {
        push @command, "--harakiri-monitor=" . $self->harakiri_addr
    } else {
        my $sock = IO::Socket::INET->new(Listen => 5);
        $self->harakiri_socket($sock);
        my $port = $self->harakiri_socket->sockport;
        log_infof("Listening on %d for harakiri", $port);
        push @command, "--harakiri-monitor=localhost:$port";
    }
    
    my $pid = fork();
    
    if($pid) {
        #Parent: setup harakiri monitoring socket
        $self->pid($pid);
        log_info("Launched CouchbaseMock PID=$pid");
        if($self->harakiri_socket) {
            $self->harakiri_socket->blocking(0);
            my $begin_time = time();
            my $max_wait = 5;
            my $got_accept = 0;
            while(time - $begin_time < $max_wait) {
                my $sock = $self->harakiri_socket->accept();
                if($sock) {
                    $self->harakiri_socket($sock);
                    $got_accept = 1;
                    log_info("Got harakiri connection");
                    my $buf;
                    $self->harakiri_socket->recv($buf, 100, 0);
                    last;
                } else {
                    sleep(0.1);
                }
            }
            if(!$got_accept) {
                die("Could not establish harakiri control connection");
            }
            $self->harakiri_socket->blocking(1);
        }
    } else {
        log_infof("Executing %s", join(" ", @command));
        exec(@command);
    }
}

sub new {
    my ($cls,%opts) = @_;
    if($INSTANCE) {
        log_warn("Returning cached instance");
        return $INSTANCE;
    }
    unless(exists $opts{url} and exists $opts{dir}) {
        die("Must have directory and URL");
    }
    my $o = $cls->_real_new(%opts);
    my $dir = $o->dir;
    my $url = URI->new($o->url);
    my $basepath = basename($url->path);
    my $fqpath = "$dir/$basepath";
    
    if(!-d $dir) {
        mkpath($dir);
    }
    
    if(!-e $fqpath) {
        log_warn("$fqpath does not exist. Downloading..");
        my $ua = LWP::UserAgent->new();
        $ua->get($url, ':content_file' => $fqpath);
    }
    
    unlink("$dir/$SYMLINK");
    symlink($fqpath, "$dir/$SYMLINK");
    
    #Initialize buckets to their defaults
    if(!$o->buckets) {
        $o->buckets([{
            name => "default",
            #does mock not support SASL?
            #password => "secret"
        }]);
    }
    
    #initialize port to the default, if not there already
    if(!$o->port) {
        $o->port(8091);
    }
    
    $o->_do_run();
    $INSTANCE = $o;
    return $o;
}

sub GetInstance {
    my $cls = shift;
    return $INSTANCE;
}

sub DESTROY {
    my $self = shift;
    kill SIGTERM, $self->pid;
    waitpid($self->pid, 0);
    log_infof("Reaped PID %d, status %d", $self->pid, $? >> 8);
    
}

1;