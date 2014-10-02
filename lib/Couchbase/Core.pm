our $VERSION;
BEGIN {
    require XSLoader;
    $VERSION = '2.0.0_2';
    XSLoader::load('Couchbase', $VERSION);
}

1;
