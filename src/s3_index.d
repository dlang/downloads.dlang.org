module s3_index;

import std.algorithm.iteration : filter, map, splitter;
import std.algorithm.searching : find, startsWith, until;
import std.exception : enforce;
import std.json;
import std.process : environment;
import std.range;
import std.stdio;
import std.string : format, strip, stripRight;
import std.typecons : tuple, Tuple;

import aws.aws;
import aws.s3;
import aws.credentials;

struct Config
{
    string aws_key;
    string aws_secret;
    string aws_region;
    string aws_endpoint;
}

auto getIniSection(string path, string section)
{
    auto lines = File(path, "r")
        .byLine
        .find!(ln => ln.strip == section);
    if (lines.empty)
        lines = File(path, "r")
            .byLine
            .find!(ln => ln.strip == "[default]");
    enforce(!lines.empty, "Failed to find ini section "~section~" in "~path~".");
    lines.popFront;
    return lines.until!(ln => ln.strip.startsWith("[")).map!readIniLine;
}

Tuple!(const(char)[], const(char)[]) readIniLine(return scope const char[] line)
{
    auto parts = line.stripRight.splitter!(c => c == ' ' || c == '=')
        .filter!(p => !p.empty);
    auto key = parts.front;
    parts.popFront;
    auto val = parts.front;
    return tuple(key, val);
}

Config loadConfig(string awsProfile)
{
    Config c;

    immutable home = environment["HOME"];

    foreach (key, val; getIniSection(home~"/.aws/credentials", "["~awsProfile~"]"))
    {
        if (key == "aws_access_key_id")
            c.aws_key = val.idup;
        else if (key == "aws_secret_access_key")
            c.aws_secret = val.idup;
    }
    enforce(!c.aws_key.empty && !c.aws_secret.empty, "Failed to parse key and secret from ~/.aws/credentials.");

    foreach (key, val; getIniSection(home~"/.aws/config", "[profile "~awsProfile~"]"))
    {
        if (key == "region")
        {
            c.aws_region = val.idup;
            c.aws_endpoint = "s3.%s.backblazeb2.com".format(val);
        }
    }
    enforce(!c.aws_endpoint.empty, "Failed to parse region from ~/.aws/config.");

    return c;
}

S3 getS3Connection(string awsProfile)
{
    auto c = loadConfig(awsProfile);

    auto creds = new StaticAWSCredentials(c.aws_key, c.aws_secret);
    auto s3 = new S3(c.aws_endpoint, c.aws_region, creds);
    return s3;
}

auto listBucketContents(S3 s3Connection, string s3Bucket)
{
    static struct S3ListResultsContentsRange
    {
        S3 s3;
        BucketListResult result;
        BucketListResult.S3Resource[] resources;
    
        this(S3 s3Connection, string s3Bucket)
        {
            s3 = s3Connection;
            result = s3.list(s3Bucket, null, null, null, 100);
            resources = result.resources;
        }
    
        BucketListResult.S3Resource front() { return resources.front; }
    
        bool empty() { return resources.empty; }
    
        void popFront()
        {
            resources.popFront;
            if (resources.empty && result.isTruncated)
            {
                auto nextResult = s3.list(result.name, null, null, result.nextMarker, 100);
                result = nextResult;
                resources = result.resources;
            }
        }
    }
    return S3ListResultsContentsRange(s3Connection, s3Bucket);
}
