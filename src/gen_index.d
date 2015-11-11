module gen_index;

import file = std.file;
import std.string;
import std.stdio;

import aws;
import s3;

import config;

//enum urlprefix = "http://downloads.dlang.org.s3-website-us-east-1.amazonaws.com";
enum urlprefix = "";

struct DirStructure
{
    string               name;
    DirStructure*        parent;
    S3Object[string]     files;   // map of filename -> S3Object, filename doesn't have directory prefixes
    DirStructure[string] subdirs; // map of dirname -> DirStructure, similar to files
}

DirStructure makeIntoDirStructure(S3ListResults contents)
{
    DirStructure dir;

    foreach(obj; contents[])
    {
        string[] nameparts = split(obj.key, "/");

        DirStructure * curdir  = &dir;
        foreach(name; nameparts[0 .. $-1])
        {
            DirStructure * nextdir = name in curdir.subdirs;
            if (!nextdir)
            {
                curdir.subdirs[name] = DirStructure();
                nextdir = name in curdir.subdirs;
                nextdir.parent = curdir;
                nextdir.name   = name;

                // check to see if a dummy directory object was added as a file
                if (name in curdir.files)
                    curdir.files.remove(name);
            }
            curdir = nextdir;
        }
        string filename = nameparts[$-1];

        // the s3sync tool creates objects that we want to ignore
        // also, the index.html files shouldn't be listed as files
        if (filename.length && !(filename in dir.subdirs) && (filename != "index.html"))
            curdir.files[filename] = obj;
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
        result ~= `<a href="` ~ urlprefix ~ accumulated ~ `">` ~ (d.length ? d : "[root]") ~ `</a>&nbsp;` ~ "\n";
    }

    return result;
}

void buildIndex(string basedir, string[] dirnames, const DirStructure[string] dirs, const S3Object[string] files)
{
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
    foreach (k; dirs.keys.sort.reverse)
    {
        string filehtml;

        filehtml ~= `<li><a href="` ~ urlprefix ~ joined ~ k ~ `/">` ~
            k ~ `</a></li>`;

        page ~= filehtml ~ "\n";
    }
    page ~= "</ul>\n";

    page ~= "Files:<br>\n<ul>\n";
    foreach (k; files.keys.sort.reverse)
    {
        string filehtml;

        filehtml ~= `<li><a href="` ~ urlprefix ~ joined ~ k ~ `">` ~
            k ~ `</a></li>`;

        page ~= filehtml ~ "\n";
    }
    page ~= "</ul>\n";

    page ~= genFooter();

    file.write(dir ~ "index.html", page);

}

void iterate(string basedir, string[] dirnames, const ref DirStructure dir)
{
    if (dir.name != "")
        dirnames ~= dir.name;

    foreach (k; dir.subdirs.keys.sort)
        iterate(basedir, dirnames, dir.subdirs[k]);

    buildIndex(basedir, dirnames, dir.subdirs, dir.files);
}

void main()
{
    load_config("config.json");

    auto a = new AWS;
    a.accessKey = c.aws_key;
    a.secretKey = c.aws_secret;
    a.endpoint = c.aws_endpoint;

    auto s3 = new S3(a);
    auto s3bucket = new S3Bucket(s3);
    s3bucket.name = c.s3_bucket;

    S3ListResults contents = listBucketContents(s3bucket);


    //writeln("contents: ", contents);

    DirStructure dir = makeIntoDirStructure(contents);

    if (c.base_dir[$-1] != '/')
        c.base_dir ~= "/";
    iterate(c.base_dir, [], dir);
}

string genHeader()
{
    return q"HEREDOC
<!DOCTYPE html>
<html lang="en-US">
<!--
    Copyright (c) 1999-2015 by Digital Mars
    All Rights Reserved Written by Walter Bright
    http://digitalmars.com
  -->
<head>
<meta charset="utf-8" />
<meta name="keywords" content="D programming language" />
<meta name="description" content="D Programming Language" />
<title>Home - D Programming Language</title>
<link rel="stylesheet" href="http://dlang.org/css/codemirror.css" />
<link rel="stylesheet" href="http://dlang.org/css/style.css" />
<link rel="stylesheet" href="http://dlang.org/css/print.css" media="print" />
<link rel="stylesheet" href="http://dlang.org/css/cssmenu.css">
<link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/font-awesome/4.2.0/css/font-awesome.min.css">
<link rel="shortcut icon" href="http://dlang.org/favicon.ico" />
<meta name="viewport" content="width=device-width, initial-scale=1.0, minimum-scale=0.1, maximum-scale=10.0" />
</head>
<body id='Home' class='doc'>
<script type="text/javascript">document.body.className += ' have-javascript';</script>
<div id="top">  <div id="header">               <a class="logo" href="http://dlang.org/"><img id="logo" width="125" height="95" alt="D Logo" src="http://dlang.org/images/dlogo.svg"></a>
                <span id="d-language-mobilehelper"><a href="http://dlang.org/" id="d-language">D Programming Language</a></span>
        </div>
</div>
<div id="navigation">    <div id="search-box">        <form method="get" action="http://google.com/search">
            <input type="hidden" id="domains" name="domains" value="dlang.org" />
            <input type="hidden" id="sourceid" name="sourceid" value="google-search" />
            <span id="search-query"><input id="q" name="q" placeholder="Search" /></span><span id="search-dropdown">                <select id="sitesearch" name="sitesearch" size="1">
                    <option value="dlang.org">Entire D Site</option>
                    <option  value="dlang.org/phobos">Library Reference</option>
                    <option value="digitalmars.com/d/archives">Newsgroup Archives</option>
                </select>
            </span><span id="search-submit"><button type="submit"><i class="fa fa-search"></i><span>go</span></button></span>
        </form>
    </div>
    
<div id="cssmenu"><ul>    <li><a href='http://dlang.org/'><span>D 2.069.1</span></a></li>
    <li><a href='http://dlang.org/download.html'><span><b>Download</b></span></a></li>
    <li><a href='http://dlang.org/getstarted.html'><span>Getting Started</span></a></li>
    <li><a href='http://dlang.org/changelog.html'><span>Change Log</span></a></li>
    <li class='has-sub'><a href='#'><span>D Reference</span></a>
      <ul><li><a href='http://dlang.org/intro.html'>Introduction</a></li><li><a href='http://dlang.org/lex.html'>Lexical</a></li><li><a href='http://dlang.org/grammar.html'>Grammar</a></li><li><a href='http://dlang.org/module.html'>Modules</a></li><li><a href='http://dlang.org/declaration.html'>Declarations</a></li><li><a href='http://dlang.org/type.html'>Types</a></li><li><a href='http://dlang.org/property.html'>Properties</a></li><li><a href='http://dlang.org/attribute.html'>Attributes</a></li><li><a href='http://dlang.org/pragma.html'>Pragmas</a></li><li><a href='http://dlang.org/expression.html'>Expressions</a></li><li><a href='http://dlang.org/statement.html'>Statements</a></li><li><a href='http://dlang.org/arrays.html'>Arrays</a></li><li><a href='http://dlang.org/hash-map.html'>Associative Arrays</a></li><li><a href='http://dlang.org/struct.html'>Structs and Unions</a></li><li><a href='http://dlang.org/class.html'>Classes</a></li><li><a href='http://dlang.org/interface.html'>Interfaces</a></li><li><a href='http://dlang.org/enum.html'>Enums</a></li><li><a href='http://dlang.org/const3.html'>Const and Immutable</a></li><li><a href='http://dlang.org/function.html'>Functions</a></li><li><a href='http://dlang.org/operatoroverloading.html'>Operator Overloading</a></li><li><a href='http://dlang.org/template.html'>Templates</a></li><li><a href='http://dlang.org/template-mixin.html'>Template Mixins</a></li><li><a href='http://dlang.org/contracts.html'>Contract Programming</a></li><li><a href='http://dlang.org/version.html'>Conditional Compilation</a></li><li><a href='http://dlang.org/traits.html'>Traits</a></li><li><a href='http://dlang.org/errors.html'>Error Handling</a></li><li><a href='http://dlang.org/unittest.html'>Unit Tests</a></li><li><a href='http://dlang.org/garbage.html'>Garbage Collection</a></li><li><a href='http://dlang.org/float.html'>Floating Point</a></li><li><a href='http://dlang.org/iasm.html'>D x86 Inline Assembler</a></li><li><a href='http://dlang.org/ddoc.html'>Embedded Documentation</a></li><li><a href='http://dlang.org/interfaceToC.html'>Interfacing to C</a></li><li><a href='http://dlang.org/cpp_interface.html'>Interfacing to C++</a></li><li><a href='http://dlang.org/portability.html'>Portability Guide</a></li><li><a href='http://dlang.org/entity.html'>Named Character Entities</a></li><li><a href='http://dlang.org/memory-safe-d.html'>Memory Safety</a></li><li><a href='http://dlang.org/abi.html'>Application Binary Interface</a></li><li><a href='http://dlang.org/simd.html'>Vector Extensions
      </a></li></ul>
    <li><a href='https://dlang.org/phobos/index.html'><span>Standard library</span></a></li>
    <li><a href='http://code.dlang.org'><span>More libraries</span></a></li>
    <li class='has-sub'><a href='#'><span>Community</span></a>
      <ul><li><a href='http://forum.dlang.org'>Forums</a></li><li><a href='irc://irc.freenode.net/d'>IRC</a></li><li><a href='http://github.com/D-Programming-Language'>D on GitHub</a></li><li><a href='http://wiki.dlang.org'>Wiki</a></li><li><a href='http://wiki.dlang.org/Review_Queue'>Review Queue</a></li><li><a href='http://twitter.com/search?q=%23dlang'>Twitter</a></li><li><a href='http://digitalmars.com/d/dlinks.html'>More Links
      </a></li></ul>
    <li class='has-sub'><a href='#'><span>Compilers &amp; Tools</span></a>
      <ul><li><a href='http://dlang.org/dmd-windows.html'>dmd &ndash; reference compiler</a></li><li><a href='http://gdcproject.org'>gdc &ndash; gcc-based compiler</a></li><li><a href='http://wiki.dlang.org/LDC'>ldc &ndash; LLVM-based compiler</a></li><li><a href='http://dlang.org/rdmd.html'>rdmd &ndash; build tool</a></li><li><a href='http://dlang.org/htod.html'>htod &ndash; .h to .d
      </a></li></ul>
    <li class='has-sub'><a href='#'><span>Books &amp; Articles</span></a>
      <ul><li><a href='http://ddili.org/ders/d.en/index.html'>Online Book (free)</a></li><li><a href='http://wiki.dlang.org/Books'>More Books</a></li><li><a href='http://dlang.org/howtos.html'>How-tos</a></li><li><a href='http://dlang.org/faq.html'>FAQ</a></li><li><a href='http://dlang.org/const-faq.html'>const(FAQ)</a></li><li><a href='http://dlang.org/comparison.html'>Feature Overview</a></li><li><a href='http://dlang.org/d-floating-point.html'>Floating Point</a></li><li><a href='http://dlang.org/wc.html'>Example: wc</a></li><li><a href='http://dlang.org/warnings.html'>Warnings</a></li><li><a href='http://dlang.org/rationale.html'>Rationale</a></li><li><a href='http://dlang.org/builtin.html'>Builtin Rationale</a></li><li><a href='http://dlang.org/ctod.html'>C to D</a></li><li><a href='http://dlang.org/cpptod.html'>C++ to D</a></li><li><a href='http://dlang.org/pretod.html'>C Preprocessor vs D</a></li><li><a href='http://dlang.org/code_coverage.html'>Code coverage analysis</a></li><li><a href='http://dlang.org/exception-safe.html'>Exception Safety</a></li><li><a href='http://dlang.org/hijack.html'>Hijacking</a></li><li><a href='http://dlang.org/intro-to-datetime.html'>Introduction to std.datetime</a></li><li><a href='http://dlang.org/lazy-evaluation.html'>Lazy Evaluation</a></li><li><a href='http://dlang.org/migrate-to-shared.html'>Migrating to Shared</a></li><li><a href='http://dlang.org/mixin.html'>Mixins</a></li><li><a href='http://dlang.org/regular-expression.html'>Regular Expressions</a></li><li><a href='http://dlang.org/safed.html'>SafeD</a></li><li><a href='http://dlang.org/templates-revisited.html'>Templates Revisited</a></li><li><a href='http://dlang.org/tuple.html'>Tuples</a></li><li><a href='http://dlang.org/variadic-function-templates.html'>Variadic Templates</a></li><li><a href='http://dlang.org/d-array-article.html'>D Slices
      </a></li></ul>
    <li class='has-sub'><a href='#'><span>Resources</span></a>
      <ul><li><a href='http://dlang.org/library/index.html'>NEW Library Reference Preview</a></li><li><a href='http://dlang.org/bugstats.php'>Bug Tracker</a></li><li><a href='http://rainers.github.io/visuald/visuald/StartPage.html'>Visual D</a></li><li><a href='http://wiki.dlang.org/Editors'>Editors</a></li><li><a href='http://wiki.dlang.org/IDEs'>IDEs</a></li><li><a href='http://dlang.org/dstyle.html'>The D Style</a></li><li><a href='http://dlang.org/glossary.html'>Glossary</a></li><li><a href='http://dlang.org/acknowledgements.html'>Acknowledgments</a></li><li><a href='http://dlang.org/sitemap.html'>Sitemap
      </a></li></ul>
</ul></div>
</div>

    <div id="news">      <div id="forum-summary">        <iframe src="http://forum.dlang.org/frame-announcements"></iframe>
        <iframe src="http://forum.dlang.org/frame-discussions"></iframe>
      </div>
      <div id="twitter">        <a class="twitter-timeline" data-dnt="true" href="https://twitter.com/D_Programming" data-widget-id="358057551562162176">Tweets by @D_Programming</a>
        <script>!function(d,s,id){var js,fjs=d.getElementsByTagName(s)[0],p=/^http:/.test(d.location)?'http':'https';if(!d.getElementById(id)){js=d.createElement(s);js.id=id;js.src=p+"://platform.twitter.com/widgets.js";fjs.parentNode.insertBefore(js,fjs);}}(document,"script","twitter-wjs");</script>
      </div>
    </div>
<div class="hyphenate" id="content">    
    
HEREDOC";
}

string genFooter()
{
    return q"HEREDOC
</div>
</body>
</html>
HEREDOC";
}
