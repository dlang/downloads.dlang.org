module config;

import std.json;
import std.file;

struct Config
{
    string aws_key;
    string aws_secret;
    string aws_endpoint;

    string s3_bucket;

    string base_dir;
}


Config load_config(string filename)
{
    string contents = cast(string)read(filename);

    JSONValue jv = parseJSON(contents);

    JSONValue aws = jv.object["aws"];
    Config c;
    c.aws_key    = aws.object["key"].str;
    c.aws_secret = aws.object["secret"].str;
    c.aws_endpoint = aws.object["endpoint"].str;

    c.s3_bucket = jv.object["s3bucket"].str;

    c.base_dir = jv.object["base_dir"].str;
    return c;
}

