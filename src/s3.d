module s3;

import std.array;
import std.datetime : SysTime;
import std.net.curl;

import aws;

class S3
{
    const AWS aws;

    this(const AWS a) { aws = a; }
}

string urlEncode(string url, bool all = false)
{
    static string encode(char c)
    {
        enum h = "0123456789ABCDEF";

        return "%" ~ h[c / 16] ~ h[c % 16];
    }

    string result;

    if (all)
    {
        foreach(c; url)
            result ~= encode(c);
    }
    else
    {
        foreach(c; url)
        {
            if ( (c >= 'A' && c <= 'Z') ||
                 (c >= 'a' && c <= 'z') ||
                 (c >= '0' && c <= '9') ||
                  c == '-'              ||
                  c == '_'              ||
                  c == '.'              ||
                  c == '~')
            {
                result ~= c;
            }
            else
            {
                result ~= encode(c);
            }
        }
    }

    return result;
}

string canonicalizedAmzHeaders(string[string] headers)
{
    import std.string : toLower, startsWith, strip;

    string[string] interesting_headers;

    foreach(key, value; headers)
    {
        string lk = key.toLower();
        if (lk.startsWith("x-amz-"))
            interesting_headers[lk] = value.strip();
    }

    string result;

    foreach(key; interesting_headers.keys.sort)
        result ~= key ~ ":" ~ headers[key] ~ "\n";

    return result;
}

string canonicalizedResource(string[string] queryArgs, string bucket, string key)
{
    string result;
    if (bucket.length) result ~= "/" ~ bucket;
    result ~= "/" ~ key;

    foreach (h; ["acl", "torrent", "location", "logging"])
    {
        if (h in queryArgs)
        {
            result ~= "?" ~ h;
            break;
        }
    }

    return result;
}

string canonicalizedQueryString(
        string method,
        string bucket,
        string key,
        string[string] queryArgs,
        string[string] headers,
        string expires)
{
    string* tmp;
    tmp = ("content-type" in headers);
    string type = (tmp ? *tmp : "");
    tmp = ("content-md5" in headers);
    string md5  = (tmp ? *tmp : "");

    return method ~ "\n" ~             // VERB
           type ~ "\n" ~               // CONTENT-TYPE
           md5 ~ "\n" ~                // CONTENT-MD5
           expires ~ "\n" ~            // time since epoch
           canonicalizedAmzHeaders(headers) ~  // always ends in an \n, so don't add another
           canonicalizedResource(queryArgs, bucket, key);
}

string concatQueryArgs(string[string] queryArgs)
{
    string result;

    foreach(k, v; queryArgs)
    {
        if (v.length)
            result ~= k ~ "=" ~ v;
        else
            result ~= k;

        result ~= "&";
    }

    return result;
}

ubyte[] makeRequest(
        const AWS a,
        string method,
        const S3Bucket bucket,
        string key,
        string[string] queryArgs,
        string[string] headers)
{
    HTTP client;
    return makeRequest(a, method, bucket, key, queryArgs, headers, client);
}

ubyte[] makeRequest(
        const AWS a,
        string method,
        const S3Bucket bucket,
        string key,
        string[string] queryArgs,
        string[string] headers,
        ref HTTP client)
{
    import std.base64;
    import std.conv;
    import std.datetime;
    import std.stdio;

    auto expires = to!string(Clock.currTime(UTC()).toUnixTime() + 600);

    auto toSign = canonicalizedQueryString(method, bucket.name, key, queryArgs, headers, expires);
    auto signed = calculateHmacSHA1(a.secretKey, toSign);
    auto b64enc = to!string(Base64.encode(to!(ubyte[])(signed)));
    auto urlenc = urlEncode(b64enc);

    string queryStr = concatQueryArgs(queryArgs) ~ "AWSAccessKeyId=" ~ a.accessKey ~ "&Expires=" ~ expires ~ "&Signature=" ~ urlenc;

    string url = "http://" ~ a.endpoint ~ "/";
    if (bucket.name.length) url ~= bucket.name ~ "/";
    if (key.length) url ~= key;
    url ~= "?" ~ queryStr;
    //writeln("url: ", url);

    ubyte[] results;
    client = HTTP();

    foreach (k, v; headers)
        client.addRequestHeader(wrap_curl_escape(k), wrap_curl_escape(v));

    try
    {
        switch (method)
        {
            case "GET":    results = get!(HTTP, ubyte)(url, client); break;
            case "DELETE": del!HTTP(url, client); break;
            default:       assert(false, "need to deal with other method types");
        }
    }
    catch(Exception e)
    {
        // TODO: do better!
        writefln("exception caught: %s", e);
    }

    return results;
}

class S3ListResults
{
    const S3Bucket bucket;

    string name;
    string prefix;
    string delimiter;
    string maxkeys;
    string marker;
    bool isTruncated;
    string nextMarker;
    S3Object[] contents;
    string[] commonPrefixes;

    this(const S3Bucket b) { bucket = b; }

    S3ListResultsContentsRange opSlice()
    {
        return S3ListResultsContentsRange(this);
    }

    void followNextMarker()
    {
        string[string] queryArgs;

        if (maxkeys.length)
            queryArgs["max-keys"] = maxkeys;
        if (prefix.length)
            queryArgs["prefix"] = prefix;
        if (delimiter.length)
            queryArgs["delimiter"] = delimiter;
        if (nextMarker.length)
            queryArgs["marker"] = nextMarker;
        else if (contents.length)
            queryArgs["marker"] = contents[$-1].key;

        import std.file;
        auto results = cast(string)makeRequest(bucket.s3.aws, "GET", bucket, "", queryArgs, null).idup;
        write("/tmp/debug.xml", results);

        // clear out previous state
        nextMarker = null;
        contents = null;
        commonPrefixes = null;
        isTruncated = false;

        parse(results);
    }

//     <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
//         <Name>puremagic-logs</Name>
//         <Prefix></Prefix>
//         <Marker></Marker>
//         <MaxKeys>1000</MaxKeys>
//         <Delimiter>/</Delimiter>
//         <IsTruncated>false</IsTruncated>
//         <Contents>
//             <Key>amanda/2012-12-15-21-21-30-C0AD6E37B4C2002B</Key>
//             <LastModified>2012-12-15T21:21:31.000Z</LastModified>
//             <ETag>&quot;faea710e9c02ace414a1fbaf5ae4a80e&quot;</ETag>
//             <Size>194684</Size>
//             <Owner>
//                 <ID>3272ee65a908a7677109fedda345db8d9554ba26398b2ca10581de88777e2b61</ID>
//                 <DisplayName>s3-log-service</DisplayName>
//             </Owner>
//             <StorageClass>STANDARD</StorageClass>
//         </Contents>
//     </ListBucketResult>
    void parse(string input)
    {
        import std.conv;
        import std.stdio;
        import std.xml;

        auto xml = new DocumentParser(input);
        xml.onEndTag["Name"] = (in Element e) { name = e.text(); };
        xml.onEndTag["Prefix"] = (in Element e) { prefix = e.text(); };
        xml.onEndTag["Delimiter"] = (in Element e) { delimiter = e.text(); };
        xml.onEndTag["Marker"] = (in Element e) { marker = e.text(); };
        xml.onEndTag["NextMarker"] = (in Element e) { nextMarker = e.text(); };
        xml.onEndTag["MaxKeys"] = (in Element e) { maxkeys = e.text(); };
        xml.onEndTag["IsTruncated"] = (in Element e) { auto trunc = e.text(); isTruncated = (trunc && trunc == "true"); };

        xml.onStartTag["Contents"] = (ElementParser xml)
        {
            auto obj = new S3Object(bucket);

            xml.onEndTag["Key"] = (in Element e) { obj.key = e.text(); };
            xml.onEndTag["LastModified"] = (in Element e)
            {
                obj.lastModified = SysTime.fromISOExtString(e.text());
            };
            xml.onEndTag["ETag"] = (in Element e) { obj.etag = e.text(); };
            xml.onEndTag["Size"] = (in Element e) { obj.size = to!long(e.text()); };
            xml.parse();

            contents ~= obj;
        };
        xml.onStartTag["CommonPrefixes"] = (ElementParser xml)
        {
            string prefix;

            xml.onEndTag["Prefix"] = (in Element e) { prefix = e.text(); };
            xml.parse();

            commonPrefixes ~= prefix;
        };
        xml.parse();
    }
}

struct S3ListResultsContentsRange
{
    S3ListResults results;

    S3Object[] contents;

    this(S3ListResults r) { results = r; contents = r.contents; }

    S3Object front() { return contents.front; }

    bool empty() { return contents.empty; }

    void popFront()
    {
        contents.popFront;
        if (contents.empty && results.isTruncated)
        {
            results.followNextMarker;
            contents = results.contents;
        }
    }
}

class S3Object
{
    const S3Bucket bucket;

    string  key;
    SysTime lastModified;
    string  etag;
    long    size   = -1;
    bool    loaded = false;
    ubyte[] data   = [];

    this(const S3Bucket b) { bucket = b; }

    ubyte[] get()
    {
        if (!loaded)
        {
            import std.conv;

            HTTP client;
            data = makeRequest(bucket.s3.aws, "GET", bucket, key, null, null, client);
            if (auto hdr = "content-length" in client.responseHeaders) size = to!long(*hdr);
            if (auto hdr = "etag" in client.responseHeaders) etag = *hdr;
            loaded = true;
        }

        return data;
    }

    void del()
    {
        import std.conv;

        HTTP client;
        ubyte[] results = makeRequest(bucket.s3.aws, "DELETE", bucket, key, null, null, client);
        assert(client.statusLine.code >= 200 && client.statusLine.code <= 299, text("delete status: ", client.statusLine));
    }
}

S3ListResults listBucketContents(const S3Bucket bucket, string prefix = null, string delimiter = null)
{
    auto results = new S3ListResults(bucket);

    results.prefix = prefix;
    results.delimiter = delimiter;
    results.maxkeys = "100";

    results.followNextMarker;

    return results;
}

class S3Bucket
{
    const S3 s3;
    string  name;
    SysTime creationDate;

    this (const S3 s) { s3 = s; }
}

S3Bucket[] listBuckets(const S3 s)
{
    import std.xml;

    auto contents = cast(string)makeRequest(s.aws, "GET", null, "", null, null).idup;

    S3Bucket[] buckets;

    auto xml = new DocumentParser(contents);
    xml.onStartTag["Buckets"] = (ElementParser xml)
    {
        xml.onStartTag["Bucket"] = (ElementParser xml)
        {
            auto bucket = new S3Bucket(s);

            xml.onEndTag["Name"] = (in Element e) { bucket.name = e.text(); };
            xml.onEndTag["CreationDate"] = (in Element e)
            {
                bucket.creationDate = SysTime.fromISOExtString(e.text());
            };
            xml.parse();

            buckets ~= bucket;
        };
        xml.parse();
    };
    xml.parse();

    return buckets;
}

