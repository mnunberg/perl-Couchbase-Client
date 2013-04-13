#!/bin/sh

# This script will automatically run Makefile.PL and build the extension
# Replace $PREFIX with whatever the common path is

PREFIX=$1
if [ -z "$PREFIX" ]; then
	PREFIX="/sources/libcouchbase/inst"
fi

make distclean
perl Makefile.PL --dynamic \
    --incpath=-I$PREFIX/include \
    --libpath=-L$PREFIX/lib $@

make
