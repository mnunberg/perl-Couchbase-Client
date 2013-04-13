#!/usr/bin/perl

# This script will generate the typemaps needed for the XS code. This
# does not need to be run each time, but might be helpful

use strict;
use warnings;

use constant {
    MODE_DEFINE => 1,
    MODE_TYPEDEF => 2
};

my $TYPEMAP = "xs/typemap";

open my $T_fh, ">", $TYPEMAP or die "$TYPEMAP: $!";


# Verify something is an IV-packed pointer, and is blessed
sub verify_ptr_isa {
    my $classname = shift;
    my $txt =<<'EOT';
if (! (SvROK($arg) && SvOBJECT(SvRV($arg)) && SvIOK(SvRV($arg)))) {
    die(\"Not a valid __CLSNAME__\");
}

EOT
    $txt =~ s/__CLSNAME__/$classname/g;
    return $txt;
}

sub verify_ptr_and_cast {
    my ($classname,$ptr_t) = @_;
    my $txt = verify_ptr_isa($classname);
    $txt .= <<"EOT";
\$var = NUM2PTR($ptr_t, SvIV(SvRV(\$arg)));
EOT
    return $txt;
}

my %Typemaps = (
    "PLCB_XS_OBJPAIR_T" =>
    {
        C_TYPE => "PLCB_XS_OBJPAIR_t",
        INPUT => verify_ptr_isa("Couchbase::Client") . <<'EOT'
$var.sv = $arg;
$var.ptr = NUM2PTR(PLCB_t*, SvIV(SvRV($arg)));
EOT
    },

    PLCB_ITER_T =>
    {
        C_TYPE => "PLCB_iter_t *",
        INPUT => verify_ptr_and_cast("Couchbase::Client::Iterator", "PLCB_iter_t*")
    },

    "PLCB_COUCH_HANDLE_T" =>
    {
        C_TYPE => "PLCB_couch_handle_t *",
        INPUT => verify_ptr_and_cast("Couchbase::Couch::RequestHandle",
            "PLCB_couch_handle_t *")
    },

    "PLCB_XS_STRING" =>
    {
        C_TYPE => "PLCB_XS_STRING_t",
        INPUT => <<'EOT'
if(!SvPOK($arg)) {
    $var.base = NULL;
    $var.len = 0;
} else {
    $var.base = SvPV($arg, $var.len);
}
$var.origsv = $arg;
EOT
    },

    "PLCB_XS_STRING_NONULL" =>
    {
        C_TYPE => "PLCB_XS_STRING_NONULL_t",
        BASE => "PLCB_XS_STRING",
        INPUT => <<'EOT'
if($var.len == 0) {
    die(\"$var cannot be empty\");
}
EOT
    },
    "PLCB_JSONDEC_T" =>
    {
        C_TYPE => "PLCB_jsondec_t*",
        INPUT => '$var = (PLCB_jsondec_t*)SvPVX(SvRV($arg));',
    }
);

select $T_fh;

print "TYPEMAP\n";
while (my ($name,$def) = each %Typemaps) {
    my $typename = $def->{C_TYPE};
    $typename =~ s/\**//g;
    $typename = "T_" . uc($typename);

    $def->{XS_TYPE} = $typename;
    printf("%s\t%s\n", $def->{C_TYPE}, $def->{XS_TYPE});
}

print "\nINPUT\n";

while (my ($name,$def) = each %Typemaps) {
    my $ctype = $def->{C_TYPE};
    my $xstype = $def->{XS_TYPE};

    my $txt = "$xstype\n";
    my $cbody = "";

    if ($def->{BASE}) {
        $cbody .= $Typemaps{$def->{BASE}}->{INPUT};
    }

    $cbody .= $def->{INPUT};

    $cbody =~ s/^/\t/msg;

    $txt .= $cbody;
    $txt .= "\n";
    print $txt;
    print "\n";
}
