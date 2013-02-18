module config;

import std.json;
import std.file;

struct Config
{
    string aws_key;
    string aws_secret;
}

Config c;

void load_config(string filename)
{
    string contents = cast(string)read(filename);

    JSONValue jv = parseJSON(contents);

    JSONValue aws = jv.object["aws"];
    c.aws_key    = aws.object["key"].str;
    c.aws_secret = aws.object["secret"].str;
}

