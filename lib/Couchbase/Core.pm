our $VERSION;
BEGIN {
    require XSLoader;
    $VERSION = '2.0.0';
    XSLoader::load('Couchbase', $VERSION);
}

1;
