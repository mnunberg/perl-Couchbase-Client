our $VERSION = '2.0.0_1';
BEGIN {
    require XSLoader;
    our $VERSION = '2.0.0_1';
    XSLoader::load('Couchbase', $VERSION);
}

1;
