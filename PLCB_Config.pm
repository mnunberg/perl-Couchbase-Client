#this perl 'hash' contains configuration information necessary
#to bootstrap and/or configure the perl couchbase client and run
#necessary tests.

{
    COUCHBASE_INCLUDE_PATH  => "/sources/libcouchbase/include",
    COUCHBASE_LIBRARY_PATH  => "/sources/libcouchbase/.libs",

    #URL from which to download the mock JAR file for tests
    COUCHBASE_MOCK_JARURL   => 
        "http://files.couchbase.com/maven2/org/couchbase/mock/".
        "CouchbaseMock/0.5-SNAPSHOT/CouchbaseMock-0.5-20120103.162550-11.jar",
};

