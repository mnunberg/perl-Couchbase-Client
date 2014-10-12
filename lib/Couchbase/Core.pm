our $VERSION;
BEGIN {
    require XSLoader;
    $VERSION = '2.0.0_3';
    XSLoader::load('Couchbase', $VERSION);
}

1;
