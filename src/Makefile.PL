#!/usr/bin/perl
package PLCBCDeps;

use strict;
use warnings;
use ExtUtils::MakeMaker;
use Dir::Self;
use Devel::CheckLib;
use Log::Fu { level => 'debug' };
use Dir::Self;
use Data::Dumper;
use File::Spec;
use Dir::Self;

use Cwd qw(abs_path);

use lib (__DIR__ . '/..');

my $Sharepath = File::Spec->catfile(
    'auto', 'share', 'dist', 'Couchbase-Client','Libary');

require ExtUtils::Liblist;

my $PARENT_MM;

my $SEARCHPATH_S;
{
    my @checklib_libs = grep $_ && $_ ne '-lcouchbase', @PLCBTopLevel::LIBS;
    $SEARCHPATH_S = join(' ', @checklib_libs) || '';
}

my %CHECKLIB_OPTIONS = (
    LIBS => $SEARCHPATH_S,
    INC => $PLCBTopLevel::INC
);

my %MM_Options = (
    NAME => 'Couchbase::libcouchbase',
    AUTHOR => q{M. Nunberg <mnunberg@haskalah.org},
    VERSION_FROM => 'libcouchbase.pm',
    ABSTRACT_FROM => 'libcouchbase.pm'
);

my $LIBCOUCHBASE_CFUNC = <<'EOC';
unsigned int version = 0;
(void)libcouchbase_get_version(&version);
if(version >= 0x010001) {
    return 0;
}
return 1;
EOC

my $LIBEVENT_CFUNC = <<EOC;
int version_major = 0, version_minor = 0;
const char *version_string = event_get_version();
if(!version_string) {
    return 1;
}
sscanf(version_string, "%d.%d", &version_major, &version_minor);
if(version_major >= 2) {
    return 0;
} else if(version_major == 1 && version_minor >= 4) {
    return 0;
}
return 1;

EOC

#sub have_


sub check_dependency {
    my ($names,$fn,%extra) = @_;
    $names = ref $names ? $names : [ $names ];
    log_info("Checking for", @$names);
    local $ENV;

    foreach my $libname (@$names) {
        my (undef,undef,$ldargs,$runpath,$sofile) =
            ExtUtils::Liblist->ext("$SEARCHPATH_S -l$libname", 0, 1);
        
        next unless ($sofile && ($sofile = $sofile->[0]) );
        
        log_info("Have:", $sofile);
        my %cl_opts = (
            %CHECKLIB_OPTIONS,
            lib => $libname,
            #libpath => "-Wl,$ldargs,$sofile",
        );
        
        if($runpath) {
            $ENV{LD_RUN_PATH} .= $runpath;
        }
        
        if($fn) {
            $cl_opts{function} = $fn;
        }
        if(check_lib(%cl_opts, %extra)) {
            log_info("have $libname");
            return 1;
        }
    }
    log_warn("Couldn't find anything for", @$names);
}


sub insert_announcement {
    my $msg = shift;
    my @lines;
    my $line = "\t\$(NOECHO)\$(ECHO) ";
    push(@lines, $line . "~" x 60) for (0..2);
    push @lines, $line . $msg;
    push(@lines, $line . "~" x 60) for (0..2);
    if(wantarray) {
        return @lines;
    } else {
        return join("\n", @lines);
    }
}

sub create_buildscript_invocation {
    my ($mm,$build,$install,$deps) = @_;
    
    #mm is the parent Makefile, here
        
    my @lines = (
        
        #begin long commandline invocation:
        
        "\t".
        #'$(NOECHO) $(ECHO) '.
        '$(PERLRUN) ' .
        File::Spec->catfile('..', 'build_libraries.pl') . "\\",
        "\t\t".sprintf(" --build-prefix=%s \\\n\t\t--install-prefix=%s",
                $mm->quote_literal($build),
                $mm->quote_literal($install)) . "\\",
        
        "\t\t".sprintf(" --env-cppflags=%s",
                $mm->quote_literal($mm->{INC})) . "\\",
        
        
        "\t\t".sprintf(" --env-libs=%s",
                $mm->quote_literal($mm->{LDLOADLIBS}. ' ' .
                    $PLCBTopLevel::U_LibPath)) . "\\",
        
        
        "\t\t".sprintf(" --rpath=%s",
                $mm->quote_literal($mm->{LD_RUN_PATH})) . "\\",
        "\t\t".join(" ", @$deps)
        
        
        
        #end long commandline invocation
        #"\t".'$(MKPATH) ' . $build,
        #"\t".'$(TOUCH) $@',
    );
    
    return @lines;

}



sub mangle_parent_makefile {
    my ($parent,$deps) = @_;
    no strict 'refs';
    
    log_warn("Mangling parent MM methods for extra dependencies");
    
    my $libpath = File::Spec->catfile($Sharepath, 'lib');
    
    my $methname = ref($parent).'::dynamic_lib';
    my $old_meth = $parent->can('dynamic_lib');
    
    my $blib_dep_path = "\$(INST_LIB)\$(DFSEP)$Sharepath";
    my $dest_dep_path = "\$(DESTINSTALLSITELIB)\$(DFSEP)$Sharepath";
    
    my $dep = "$blib_dep_path\$(DFSEP)lib\$(DFSEP)libcouchbase.\$(SO)";
    
    $parent->{MYEXTLIB} = $dep;
    
    *{ref($parent) . "::dynamic_lib"} = sub {
        my ($mm,@args) = @_;
        my $ret = $old_meth->($mm,@args, INST_DYNAMIC_DEP => $dep);
        $ret = join("\n",
            "\$(MYEXTLIB) ::",
            "\t\$(NOOP)",
        ) . $ret;
        
        return $ret;
    };
    
    my $ldload = $parent->{LDLOADLIBS} || "";
    my $runpath = $parent->{LD_RUN_PATH} || "";
    
    
    $runpath = "$blib_dep_path\$(DFSEP)lib:" .
                "$dest_dep_path\$(DFSEP)lib".
                ":$runpath";
    $ldload = "-L$blib_dep_path\$(DFSEP)lib";
        
    {
        my $parent_dir = abs_path("..");
        $parent->{INST_LIB} = File::Spec->catfile($parent_dir,
                                                  $parent->{INST_LIB});
    }
        
    $parent->{LDLOADLIBS} = $ldload;
    $parent->{LD_RUN_PATH} = $runpath;
    
    $parent->{INC} .= " -I$blib_dep_path\$(DFSEP)include";
    
    
    my $parent_inc = $parent->{INC};
    
    my $inc_oneliner = sprintf("PLCB_ConfUtil::write_tmpflags(qq{%s})",
                               $parent_inc);
    
    no warnings qw(redefine once);
    *MY::postamble = sub {
        my @lines = (
            #get an absolute reference to $(INST_LIB)
            
            #"INST_LIB := ".
            #'$(shell '.
            #    $parent->oneliner('print abs_path("$(INST_LIB)")',
            #                      [ '-MCwd=abs_path' ])
            #.' )',
            
            "$dep:",
            (insert_announcement("will build for ultimate target $dep")),
            (create_buildscript_invocation($parent,
                    $blib_dep_path, $dest_dep_path, $deps)),
            (insert_announcement("dependencies done")),
            
            #now try to insert some constants.
            "\t".$parent->oneliner($inc_oneliner, ['-I../', '-MPLCB_ConfUtil']),
            "",
            "",
            
            
            "all :: $dep",
        );
        
        return join("\n", @lines);
    };   
}

sub MM_Configure {
    my ($self,$h) = @_;
    my $parent = $ExtUtils::MakeMaker::Parent[0];
    $PLCBTopLevel::MM_TopLevel = $parent;
    
    $PARENT_MM = $parent;
    die("Must be run from within top-level Makefile.PL") unless $parent;
    my @to_build;
    
    if($ENV{PLCB_BUILD_ALL}) {
        log_err('build_all reuqested');
        @to_build = qw(VBUCKET COUCHBASE EVENT ISASL);
        goto GT_MANGLE;
    }
    
    my $have_libcouchbase =
        check_dependency('couchbase',$LIBCOUCHBASE_CFUNC);
    
    if($have_libcouchbase) {
        
        return $h; #nothing to do here.
    } else {
        push @to_build, qw(COUCHBASE VBUCKET);
    }
    
    if(!check_dependency(
        'event', $LIBEVENT_CFUNC, header => 'event.h')) {
        push @to_build, 'EVENT';
    }
    if(!check_dependency(['sasl2', 'sasl', 'isasl'])) {
        push @to_build, 'ISASL';
    }
    
    GT_MANGLE:
    log_err("We need to build the following dependencies:", @to_build);
    mangle_parent_makefile($parent, \@to_build);
    
    
    return $h;

}

$MM_Options{CONFIGURE} = \&MM_Configure;

WriteMakefile(%MM_Options);