module config;

import std.algorithm.iteration : filter, map, splitter;
import std.algorithm.searching : find, startsWith, until;
import std.exception : enforce;
import std.json;
import std.process : environment;
import std.range : empty;
import std.stdio;
import std.string : format, strip, stripRight;
import std.typecons : tuple, Tuple;

struct Config
{
    string aws_key;
    string aws_secret;
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
            c.aws_endpoint = "s3-%s.amazonaws.com".format(val);
    }
    enforce(!c.aws_endpoint.empty, "Failed to parse region from ~/.aws/config.");

    return c;
}
