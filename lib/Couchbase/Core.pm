our $VERSION;
BEGIN {
    require XSLoader;
    $VERSION = '2.0.0_4';
    XSLoader::load('Couchbase', $VERSION);
}

1;
