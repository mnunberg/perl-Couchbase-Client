package PLCB_ConfUtil;
use strict;
use warnings;
use Dir::Self;
use lib __DIR__;

my $config = do 'PLCB_Config.pm';
if(!$config) {
    warn("Couldn't find PLCB_Config.pm. Assuming defaults");
    $config = {};
}

sub set_gcc_env {
    my $existing_env = $ENV{C_INCLUDE_PATH};
    $existing_env ||= "";
    my $new_env = $config->{COUCHBASE_INCLUDE_PATH};
    if(!$new_env) {
        return;
    } else {
        $ENV{C_INCLUDE_PATH} = "$new_env:$existing_env";
    }
}

sub get_gcc_linker_flags {
    my $libpath = $config->{COUCHBASE_LIBRARY_PATH};
    if($libpath) {
        $libpath = "-L$libpath ";
    } else {
        $libpath = "";
    }
    $libpath .= '-lcouchbase -lcouchbase_libevent -lvbucket';
    return $libpath;
}

sub get_include_dir {
    my $dir = $config->{COUCHBASE_INCLUDE_PATH};
    if($dir) {
        return "-I$dir";
    } else {
        return "";
    }
}

1;
