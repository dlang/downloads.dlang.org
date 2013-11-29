module s3;

import etc.c.curl;
import std.net.curl;

import std.algorithm;
import std.base64;
import std.conv;
import std.datetime;
import std.stdio;
import std.string;
import std.xml;

import aws;

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

char[] makeRequest(
        const ref AWS a,
        string method,
        string bucket,
        string key,
        string[string] queryArgs,
        string[string] headers)
{
    auto expires = to!string(Clock.currTime(UTC()).toUnixTime() + 600);

    auto toSign = canonicalizedQueryString(method, bucket, key, queryArgs, headers, expires);
    auto signed = calculateHmacSHA1(a.secretKey, toSign);
    auto b64enc = to!string(Base64.encode(to!(ubyte[])(signed)));
    auto urlenc = urlEncode(b64enc);

    string queryStr = concatQueryArgs(queryArgs) ~ "AWSAccessKeyId=" ~ a.accessKey ~ "&Expires=" ~ expires ~ "&Signature=" ~ urlenc;

    string url = "http://" ~ a.endpoint ~ "/";
    if (bucket.length) url ~= bucket ~ "/";
    if (key.length) url ~= key;
    url ~= "?" ~ queryStr;

    char[] results;
    auto client = HTTP();

    foreach (k, v; headers)
        client.addRequestHeader(wrap_curl_escape(k), wrap_curl_escape(v));

    try
    {
        assert(method == "GET", "need to deal with other method types");
        results = get(url, client);
    }
    catch(Exception e)
    {
        writefln("exception caught: %s", e);
    }
    
    return results;
}

struct S3ListResults
{
    string name;
    string prefix;
    string maxkeys;
    string istruncated;
    S3Object[] contents;
}

struct S3Object
{
    string  key;
    SysTime lastModified;
    string  etag;
    long    size;
}

S3ListResults listBucketContents(const ref AWS a, string bucket, string prefix = null)
{
    string[string] queryArgs;
    if (prefix.length)
        queryArgs["prefix"] = prefix;

    string contents = makeRequest(a, "GET", bucket, "", queryArgs, null).idup;
    //writeln("contents: ", contents);

    S3ListResults results;

    auto xml = new DocumentParser(contents);
    xml.onEndTag["Name"] = (in Element e) { results.name = e.text(); };
    xml.onEndTag["Prefix"] = (in Element e) { results.prefix = e.text(); };
    xml.onEndTag["MaxKeys"] = (in Element e) { results.maxkeys = e.text(); };
    xml.onEndTag["IsTruncated"] = (in Element e) { results.istruncated = e.text(); };

    xml.onStartTag["Contents"] = (ElementParser xml)
    {
        S3Object obj;

        xml.onEndTag["Key"] = (in Element e) { obj.key = e.text(); };
        xml.onEndTag["LastModified"] = (in Element e)
        {
            obj.lastModified = SysTime.fromISOExtString(e.text());
        };
        xml.onEndTag["ETag"] = (in Element e) { obj.etag = e.text(); };
        xml.onEndTag["Size"] = (in Element e) { obj.size = to!long(e.text()); };
        xml.parse();

        results.contents ~= obj;
    };
    xml.parse();

    return results;
}

//     <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
//         <Name>puremagic-logs</Name>
//         <Prefix></Prefix>
//         <Marker></Marker>
//         <MaxKeys>1000</MaxKeys>
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

struct S3Bucket
{
    string  name;
    SysTime creationDate;
}

S3Bucket[] listBuckets(const ref AWS a)
{
    string contents = makeRequest(a, "GET", "", "", null, null).idup;

    S3Bucket[] buckets;

    auto xml = new DocumentParser(contents);
    xml.onStartTag["Buckets"] = (ElementParser xml)
    {
        xml.onStartTag["Bucket"] = (ElementParser xml)
        {
            S3Bucket bucket;

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

