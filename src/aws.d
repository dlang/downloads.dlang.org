module aws;

import etc.c.curl;
import std.net.curl;
import std.base64;
import std.conv;
import std.datetime;
import std.string;
import std.stdio;

class AWS
{
    string accessKey;
    string secretKey;

    string endpoint() @property const { return _endpoint; }
    string endpoint(string e) @property { _endpoint = toLower(e); return _endpoint; }

    private:
        string _endpoint;
}

/**
 * Constructs the query string parameters for an aws requests.
 * NOTE: uses the v2 signing method
 */
string buildQueryString(const ref AWS aws, const(char)[] httpVerb, const(char)[] requestURI, string[string] params)
{
    auto expires = (Clock.currTime(UTC()) + dur!"minutes"(10)); // set expiration for now + 10 minutes
    expires.fracSec(FracSec.from!"msecs"(0)); // aws doesn't want fractions of a second, so get rid of them

    params["AWSAccessKeyId"]   = aws.accessKey;
    params["Expires"]          = expires.toISOExtString();
    params["SignatureVersion"] = "2";
    params["SignatureMethod"]  = "HmacSHA256";

    auto cannon = cannonicalizeQueryString(params);
    auto toSign =
        httpVerb ~ "\n" ~
        aws.endpoint ~ "\n" ~
        requestURI ~ "\n" ~
        cannon;

    auto signed = calculateHmacSHA256(aws.secretKey, toSign);
    auto b64enc = to!string(Base64.encode(to!(ubyte[])(signed)));

    return cannon ~ "&Signature=" ~ wrap_curl_escape(b64enc);
}

// curl's api is a tad painful to call and cleanup after correctly, so hiding that here.
string wrap_curl_escape(string s)
{
    if (!s)
        return "";

    auto sptr = cast(char*)s.ptr; // curl's api wants a mutable, but almost certainly doesn't mutate it
    auto slen = to!int(s.length);

    auto ret = curl_escape(sptr, slen);
    auto retStr = to!string(ret);
    curl_free(ret);

    return retStr;
}

private string cannonicalizeQueryString(const ref string[string] params)
{
    auto output = "";
    auto first = true;

    foreach (s; params.keys.sort)
    {
        if (!first)
            output ~= "&";
        else
            first = false;

        output ~= wrap_curl_escape(s) ~ "=" ~ wrap_curl_escape(params[s]);
        writeln();
    }

    return output;
}

// TODO: create a real crypto package that the stuff can live in
extern(C)
{
    struct EVP_MD;

    const(EVP_MD)* EVP_sha1();
    const(EVP_MD)* EVP_sha256();

    ubyte *HMAC(const(EVP_MD)* evp_md,
                const void  *key, int    key_len,
                const ubyte *d,   size_t n,
                      ubyte *md,  uint  *md_len);

    enum EVP_MAX_MD_SIZE = 64;
}

string calculateHmacSHA256(string secret, const(char)[] data)
{
    ubyte* keyPtr = cast(ubyte*)secret.ptr;
    int    keyLen = to!int(secret.length);

    ubyte* dataPtr = cast(ubyte*)data.ptr;
    size_t dataLen = to!size_t(data.length);

    ubyte result[EVP_MAX_MD_SIZE];
    uint  resultLen = result.length;

    ubyte* rc = HMAC(EVP_sha256(), keyPtr, keyLen, dataPtr, dataLen, result.ptr, &resultLen);

    return to!string(rc[0 .. resultLen]);
}

string calculateHmacSHA1(string secret, const(char)[] data)
{
    ubyte* keyPtr = cast(ubyte*)secret.ptr;
    int    keyLen = to!int(secret.length);

    ubyte* dataPtr = cast(ubyte*)data.ptr;
    size_t dataLen = to!size_t(data.length);

    ubyte result[EVP_MAX_MD_SIZE];
    uint  resultLen = result.length;

    ubyte* rc = HMAC(EVP_sha1(), keyPtr, keyLen, dataPtr, dataLen, result.ptr, &resultLen);

    return to!string(rc[0 .. resultLen]);
}

// TODO: redo on top of std.net.curl
// unittest
// {
//     //import core.stdc.stdio;
//     import std.process;
// 
//     AWS aws;
//     aws.curl = curl_easy_init(); // in real code, only init once
//     aws.accessKey = Environment["AWS_ACCESS_KEY"];
//     aws.secretKey = Environment["AWS_SECRET_KEY"];
//     aws.endpoint  = "ec2.amazonaws.com";
// 
//     string[string] params = [
//         "Action" : "DescribeRegions",
//         "Version" : "2011-07-15"
//     ];
// 
//     string queryStr = buildQueryString(aws, "GET", "/", params);
// 
//     curl_easy_setopt(aws.curl, CurlOption.verbose, 1);
//     curl_easy_setopt(aws.curl, CurlOption.url, toStringz("https://" ~ aws.endpoint ~ "/?" ~ queryStr));
//     CURLcode res = curl_easy_perform(aws.curl);
// 
//     curl_easy_cleanup(aws.curl);
// 
//     assert(false);
// }

