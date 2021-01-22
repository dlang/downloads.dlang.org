module gen_index;

import file = std.file;
import std.algorithm;
import std.file;
import std.json;
import std.string;
import std.stdio;

import aws;
import s3;

import config;

//enum urlprefix = "http://downloads.dlang.org.s3-website-us-east-1.amazonaws.com";
enum urlprefix = "";

struct DirStructure
{
    bool isSymlink; // directory is a symlink to another dir
    bool[string]         files;   // set of filenames, filename doesn't have directory prefixes
    DirStructure[string] subdirs; // map of dirname -> DirStructure, similar to files
}

enum SymlinkDir = DirStructure(true);

DirStructure makeIntoDirStructure(R)(R entries)
{
    DirStructure dir;

    foreach(entry; entries)
    {
        string[] nameparts = split(entry.path, "/");

        DirStructure * curdir  = &dir;
        foreach(name; nameparts[0 .. $-1])
        {
            DirStructure * nextdir = name in curdir.subdirs;
            if (!nextdir)
            {
                curdir.subdirs[name] = DirStructure();
                nextdir = name in curdir.subdirs;

                // check to see if a dummy directory object was added as a file
                if (name in curdir.files)
                    curdir.files.remove(name);
            }
            curdir = nextdir;
        }
        string filename = nameparts[$-1];

        if (entry.isSymlinkDir)
            curdir.subdirs[filename] = SymlinkDir;
        // the s3sync tool creates objects that we want to ignore
        // also, the index.html files shouldn't be listed as files
        else if (filename.length && !(filename in dir.subdirs) && (filename != "index.html"))
            curdir.files[filename] = true;
    }

    return dir;
}

JSONValue toJSON(DirStructure dir)
{
    JSONValue res;
    res["files"] = JSONValue(dir.files.keys);
    if (dir.subdirs)
    {
        JSONValue subdirs;
        foreach (k, v; dir.subdirs)
            subdirs[k] = v.isSymlink ? JSONValue(null) : toJSON(v);
        res["subdirs"] = subdirs;
    }
    return res;
}

DirStructure fromJSON(JSONValue json)
{
    DirStructure dir;
    foreach (v; json["files"].array)
        dir.files[v.str] = true;
    if (auto p = "subdirs" in json.object)
    {
        foreach (k, v; p.object)
            dir.subdirs[k] = v.isNull ? SymlinkDir : fromJSON(v);
    }
    return dir;
}

string dirlinks(string[] dirnames)
{

    string result = "<a href=\"" ~ urlprefix ~ "/\">[root]</a>&nbsp;\n";

    string accumulated = "/";

    foreach (d; dirnames)
    {
        accumulated ~= d ~ "/";
        result ~= `<a href="` ~ urlprefix ~ accumulated ~ `index.html">` ~ (d.length ? d : "[root]") ~ `</a>&nbsp;` ~ "\n";
    }

    return result;
}

void buildIndex(string basedir, string[] dirnames, const DirStructure[string] dirs, const bool[string] files)
{
    import std.range : retro;

    writefln("dirnames: %s", dirnames);
    string joined = "/" ~ join(dirnames, "/");
    joined = (joined != "/" ? (joined ~ "/") : "");

    writefln("generating index for: %s", joined);

    string dir = basedir ~ joined;

    if (!file.exists(dir))
        file.mkdirRecurse(dir);

    string page = genHeader();

    page ~= "<h2>" ~ dirlinks(dirnames) ~ "</h2>\n";

    page ~= "Subdirectories:<br>\n<ul>\n";
    foreach (k; dirs.keys.sort().retro)
    {
        string filehtml;

        filehtml ~= `<li><a href="` ~ urlprefix ~ joined ~ k ~ `/index.html">` ~
            k ~ `</a></li>`;

        page ~= filehtml ~ "\n";
    }
    page ~= "</ul>\n";

    page ~= "Files:<br>\n<ul>\n";
    foreach (k; files.keys.sort().retro)
    {
        string filehtml;

        filehtml ~= `<li><a href="https://s3.us-west-2.amazonaws.com/downloads.dlang.org` ~ urlprefix ~ joined ~ k ~ `">` ~
            k ~ `</a></li>`;

        page ~= filehtml ~ "\n";
    }
    page ~= "</ul>\n";

    page ~= genFooter();

    file.write(dir ~ "index.html", page);

}

void iterate(string basedir, string[] dirnames, const ref DirStructure dir)
{
    foreach (name; dir.subdirs.keys.sort())
    {
        auto subdir = dir.subdirs[name];
        if (!subdir.isSymlink)
            iterate(basedir, dirnames ~ name, dir.subdirs[name]);
    }

    buildIndex(basedir, dirnames, dir.subdirs, dir.files);
}

S3Bucket getBucket(string awsProfile, string s3Bucket)
{
    auto c = loadConfig(awsProfile);

    auto a = new AWS;
    a.accessKey = c.aws_key;
    a.secretKey = c.aws_secret;
    a.endpoint = c.aws_endpoint;

    auto s3 = new S3(a);
    auto s3bucket = new S3Bucket(s3);
    s3bucket.name = s3Bucket;
    return s3bucket;
}

int main(string[] args)
{
    import std.getopt : config, getopt, defaultGetoptPrinter;

    auto awsProfile = "ddo";
    auto jsonPath = "index.json";
    auto outputPath = "./ddo/";
    auto s3Bucket = "downloads.dlang.org";
    string[] commands;
    // dfmt off
    auto helpInformation = getopt(
        args,
        config.passThrough,
        config.required,
        "c|command", "Commands to run (can be specified multiple times).", &commands,
        "aws-profile", "AWS profile name to use (default %s).".format(awsProfile), &awsProfile,
        "s3-bucket", "S3 Bucket to index (default %s).".format(s3Bucket), &s3Bucket,
        "json-path", "Path to write json index to (default %s).".format(jsonPath), &jsonPath,
        "output-path", "Folder to generate index.html files to (default %s).".format(outputPath), &outputPath,
    );
    // dfmt on
    if (helpInformation.helpWanted)
    {
        defaultGetoptPrinter(args[0]~"\n", helpInformation.options);
        return 0;
    }

    foreach (ref idx, command; commands)
    {
        import std.typecons : tuple;

        switch (command)
        {
        case "s3_index":
            if (file.exists(jsonPath))
                file.remove(jsonPath); // remove stale data
            auto dir = getBucket(awsProfile, s3Bucket)
                .listBucketContents
                .map!(o => tuple!("path", "isSymlinkDir")(o.key, false))
                .makeIntoDirStructure();
            file.write(jsonPath, toJSON(dir).toPrettyString);
            break;

        case "folder_index":
            if (file.exists(jsonPath))
                file.remove(jsonPath); // remove stale data
            auto path = args[1 + ++idx].chomp("/") ~ "/";
            enum followSymlink = true;
            auto dir = dirEntries(path, SpanMode.breadth, !followSymlink)
                .filter!(de => de.isFile || de.isSymlink && de.isDir)
                .map!(de => tuple!("path", "isSymlinkDir")(de.name.chompPrefix(path), de.isSymlink))
                .makeIntoDirStructure();
            file.write(jsonPath, toJSON(dir).toPrettyString);
            break;

        case "generate":
            auto dir = fromJSON(file.readText(jsonPath).parseJSON);
            iterate(outputPath, [], dir);
            break;

        default:
            assert(0, "Unknown command "~command);
        }
    }
    return 0;
}

string genHeader()
{
    return q"HEREDOC


<!DOCTYPE html>
<html lang="en-US">
<!--
    Copyright (c) 1999-2016 by Digital Mars
    All Rights Reserved Written by Walter Bright
    http://digitalmars.com
  -->
<head>
<meta charset="utf-8">
<meta name="keywords" content="D programming language">
<meta name="description" content="D Programming Language">
<title>Release Archive - D Programming Language</title>

<link rel="stylesheet" href="//dlang.org/css/codemirror.css">
<link rel="stylesheet" href="//dlang.org/css/style.css">
<link rel="stylesheet" href="//dlang.org/css/print.css" media="print">
<link rel="shortcut icon" href="//dlang.org/favicon.ico">
<meta name="viewport" content="width=device-width, initial-scale=1.0, minimum-scale=0.1, maximum-scale=10.0">

</head>
<body id='ReleaseArchive'>
<script type="text/javascript">document.body.className += ' have-javascript'</script>
<div id="top"><div class="helper"><div class="helper expand-container">    <div class="logo"><a href="http://dlang.org"><img id="logo" alt="D Logo" src="//dlang.org/images/dlogo.svg"></a></div>
    <a href="http://dlang.org/menu.html" title="Menu" class="hamburger expand-toggle"><span>Menu</span></a>

<div id="cssmenu"><ul>    <li><a href='http://dlang.org/getstarted.html'><span>Learn</span></a></li>
    <li class='expand-container'><a class='expand-toggle' href='http://dlang.org/documentation.html'><span>Documentation</span></a>

<ul class='expand-content'><li><a href='http://dlang.org/spec/intro.html'>Language Reference</a></li><li><a href='http://dlang.org/phobos/index.html'>Library Reference</a></li><li><a href='http://dlang.org/comparison.html'>Feature Overview</a></li><li><a href='http://dlang.org/dmd-windows.html'>DMD Manual</a></li><li><a href='http://dlang.org/articles.html'>Articles
</a></li></ul></li>
    <li><a href='http://dlang.org/download.html'><span>Downloads</span></a></li>
    <li><a href='http://code.dlang.org'><span>Packages</span></a></li>
    <li class='expand-container'><a class='expand-toggle' href='http://dlang.org/community.html'><span>Community</span></a>

<ul class='expand-content'><li><a href='http://dlang.org/bugstats.php'>Bug Tracker</a></li><li><a href='    http://forum.dlang.org'>Forums</a></li><li><a href='    irc://irc.freenode.net/d'>IRC</a></li><li><a href='    http://github.com/dlang'>D on GitHub</a></li><li><a href='    http://wiki.dlang.org'>Wiki</a></li><li><a href='    http://wiki.dlang.org/Review_Queue'>Review Queue</a></li><li><a href='    http://twitter.com/search?q=%23dlang'>Twitter</a></li><li><a href='    http://digitalmars.com/d/dlinks.html'>More Links
</a></li></ul></li>
    <li class='expand-container'><a class='expand-toggle' href='http://dlang.org/resources.html'><span>Resources</span></a>

<ul class='expand-content'><li><a href='http://dlang.org/library/index.html'>NEW Library Reference Preview</a></li><li><a href='http://dlang.org/tools.html'>D-Specific Tools</a></li><li><a href='    http://rainers.github.io/visuald/visuald/StartPage.html'>Visual D</a></li><li><a href='    http://wiki.dlang.org/Editors'>Editors</a></li><li><a href='    http://wiki.dlang.org/IDEs'>IDEs</a></li><li><a href='    http://wiki.dlang.org/Tutorials'>Tutorials</a></li><li><a href='    http://wiki.dlang.org/Books'>Books</a></li><li><a href='http://dlang.org/dstyle.html'>The D Style</a></li><li><a href='http://dlang.org/glossary.html'>Glossary</a></li><li><a href='http://dlang.org/acknowledgements.html'>Acknowledgments</a></li><li><a href='http://dlang.org/sitemap.html'>Sitemap
</a></li></ul></li>
</ul></div>
    <div class="search-container expand-container">        <a href="http://dlang.org/search.html" class="expand-toggle" title="Search"><span>Search</span></a>

    <div id="search-box">        <form method="get" action="//google.com/search">
            <input type="hidden" id="domains" name="domains" value="dlang.org">
            <input type="hidden" id="sourceid" name="sourceid" value="google-search">
            <span id="search-query"><input id="q" name="q" placeholder="Search"></span><span id="search-dropdown"><span class="helper">                <select id="sitesearch" name="sitesearch" size="1">
                    <option value="dlang.org">Entire Site</option>
                    <option  value="dlang.org/spec">Language</option>
                    <option  value="dlang.org/phobos">Library</option>
                    <option  value="forum.dlang.org">Forums</option>

                </select>
            </span></span><span id="search-submit"><button type="submit"><i class="fa fa-search"></i><span>go</span></button></span>
        </form>
    </div>
    </div>
</div></div></div>

<div class="container">
    <div class="hyphenate" id="content">
HEREDOC";
}

string genFooter()
{
    return q"HEREDOC
    </div>
</div>

    <script type="text/javascript" src="https://ajax.googleapis.com/ajax/libs/jquery/1.7.2/jquery.min.js"></script>
    <script type="text/javascript">window.jQuery || document.write('\x3Cscript src="js/jquery-1.7.2.min.js">\x3C/script>');</script>
    <script type="text/javascript" src="//dlang.org/js/dlang.js"></script>

<link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/font-awesome/4.2.0/css/font-awesome.min.css">
</body>
</html>
HEREDOC";
}
