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

    string result;

    string accumulated;

    foreach (d; dirnames)
    {
        accumulated ~= d ~ "/";
        result ~= `<a href="` ~ urlprefix ~ accumulated ~ `">` ~ (d.length ? d : "[root]") ~ `</a>&nbsp` ~ "\n";
    }

    return result;
}

void buildIndex(string[] dirnames, const DirStructure[string] dirs, const S3Object[string] files)
{
    string joined = join(dirnames, "/");
    writefln("generating index for: %s", joined);

    string dir = "/mnt/downloads.dlang.org/" ~ joined ~ "/";

    if (!file.exists(dir))
        file.mkdirRecurse(dir);

    string page = genHeader();

    page ~= "<h2>" ~ dirlinks(dirnames) ~ "</h2>\n";

    page ~= "Subdirectories:<br>\n<ul>\n";
    foreach (k; dirs.keys.sort.reverse)
    {
        string filehtml;

        filehtml ~= `<li><a href="` ~ urlprefix ~ joined ~ "/" ~ k ~ `/">` ~
            k ~ `</a></li>`;

        page ~= filehtml ~ "\n";
    }
    page ~= "</ul>\n";

    page ~= "Files:<br>\n<ul>\n";
    foreach (k; files.keys.sort.reverse)
    {
        string filehtml;

        filehtml ~= `<li><a href="` ~ urlprefix ~ joined ~ "/" ~ k ~ `">` ~
            k ~ `</a></li>`;

        page ~= filehtml ~ "\n";
    }
    page ~= "</ul>\n";

    page ~= genFooter();

    file.write(dir ~ "index.html", page);

}

void iterate(string[] dirnames, const ref DirStructure dir)
{
    dirnames ~= dir.name;

    foreach (k; dir.subdirs.keys.sort)
        iterate(dirnames, dir.subdirs[k]);

    buildIndex(dirnames, dir.subdirs, dir.files);
}

void main()
{
    load_config("config.json");

    auto a = new AWS;
    a.accessKey = c.aws_key;
    a.secretKey = c.aws_secret;
    a.endpoint = "s3.amazonaws.com";

    auto s3 = new S3(a);
    auto s3bucket = new S3Bucket(s3);
    s3bucket.name = "downloads.dlang.org";

    S3ListResults contents = listBucketContents(s3bucket);


    //writeln("contents: ", contents);

    DirStructure dir = makeIntoDirStructure(contents);

    iterate([], dir);
}

string genHeader()
{
    return q"HEREDOC
<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">
<html lang="en-US">

<!--
Copyright (c) 1999-2013 by Digital Mars
All Rights Reserved Written by Walter Bright
http://digitalmars.com
  -->

<head>
<meta http-equiv="content-type" content="text/html; charset=utf-8" />
<title>D Programming Language</title>
<link rel="stylesheet" href="http://dlang.org/css/codemirror.css" />
<link rel="stylesheet" type="text/css" href="http://dlang.org/css/style.css" />
<link rel="stylesheet" type="text/css" href="http://dlang.org/css/print.css" media="print" />
<script src="https://ajax.googleapis.com/ajax/libs/jquery/1.7.2/jquery.min.js" type="text/javascript"></script>
<script src="http://dlang.org/js/codemirror.js"></script>
<script src="http://dlang.org/js/run-main-website.js" type="text/javascript"></script>
<script src="http://dlang.org/js/d.js"></script>
<script src="http://dlang.org/js/run.js" type="text/javascript"></script>

<link rel="shortcut icon" href="http://dlang.org/favicon.ico" />

<script src="http://dlang.org/js/hyphenate.js" type="text/javascript"></script>

<script type="text/javascript">
function bodyLoad()
{
var links = document.getElementById("navigation").getElementsByTagName("a");
for (var i = 0; i < links.length; i++)
{
var url = "/" + links[i].getAttribute("href");
if (window.location.href.match(url + "\x24") == url)
{
var cls = links[i].getAttribute("class");
links[i].setAttribute("class", cls ? cls + " active" : "active");
break;
}
}
}
</script>
</head>

<body onLoad='bodyLoad()'>

<div id="top">
<div id="search-box">
<form method="get" action="http://google.com/search">
<img src="http://dlang.org/images/search-left.gif" width="11" height="22" /><input id="q" name="q" /><input type="image" id="search-submit" name="submit" src="http://dlang.org/images/search-button.gif" />
<input type="hidden" id="domains" name="domains" value="dlang.org" />
<input type="hidden" id="sourceid" name="sourceid" value="google-search" />
<div id="search-dropdown">
<select id="sitesearch" name="sitesearch" size="1">
<option value="dlang.org">Entire D Site</option>
<option value="dlang.org/phobos">Library Reference</option>
<option value="digitalmars.com/d/archives">Newsgroup Archives</option>
</select>
</div>
</form>
</div>
<div id="header">
<a id="d-language" href="http://dlang.org/">
<img id="logo" width="125" height="95" border="0" alt="D Logo" src="http://dlang.org/images/dlogo.png">
D Programming Language</a>
</div>
</div>


<div id="navigation">
  

<div class="navblock">
<h2><a href="http://dlang.org/index.html" title="D Programming Language">D Home</a></h2>
<ul><li><a href="http://dlang.org/overview.html" title="D language overview">Overview</a></li>
        <li><a href="http://dlang.org/comparison.html" title="D feature list">Features</a></li>
        <li><a href="http://dlang.org/download.html" title="Download a D compiler">Downloads &amp; Tools</a></li>
        <li><a href="http://dlang.org/changelog.html" title="History of changes to D">Change Log</a></li>
        <li><a href="http://dlang.org/bugstats.php" title="D issue and bug tracking system">Bug Tracker</a></li>
        <li><a href="http://dlang.org/faq.html" title="Frequently Asked Questions">FAQ</a></li>
        <li><a href="http://dlang.org/appendices.html">Appendices</a></li>
        <li><a href="http://dlang.org/acknowledgements.html" title="Thank-you to these people who have helped with D">Acknowledgments</a></li>
        <li><a href="http://dlang.org/sitemap.html" title="Documents on this site, indexed alphabetically">Sitemap</a></li>
        <li><a href="http://digitalmars.com/d/1.0/index.html" title="D Programming Language 1.0">D1 Home</a></li>
</ul>
    </div>

<div class="navblock">
<h2>Documentation</h2>
<ul>   <li><a href="http://www.amazon.com/exec/obidos/ASIN/0321635361/classicempire">Book</a></li>
        <li><a href="http://www.informit.com/articles/article.aspx?p=1381876">&nbsp;<font size=-1><span style="visibility: hidden">3</span>1.&nbsp;Tutorial</font></a></li>
        <li><a href="http://www.informit.com/articles/article.aspx?p=1609144">&nbsp;<font size=-1>13.&nbsp;Concurrency</font></a></li>

        <li><a href="http://dlang.org/language-reference.html">Language Reference</a></li>
        <li><a href="http://dlang.org/phobos/index.html">Library Reference</a></li>
        <li><a href="http://dlang.org/howtos.html" title="Helps for using D">How-tos</a></li>
        <li><a href="http://dlang.org/articles.html">Articles</a></li>
</ul>
    </div>

<div class="navblock">
<h2>Community</h2>
<ul><li><a href="http://forum.dlang.org/" title="User forums">Forums</a></li>
        <li><a href="http://github.com/D-Programming-Language" title="D on github">GitHub</a></li>
        <li><a href="http://prowiki.org/wiki4d/wiki.cgi?FrontPage" title="Wiki for the D Programming Language">Wiki</a></li>
        <li><a href="http://prowiki.org/wiki4d/wiki.cgi?ReviewQueue" title="Queue of current and upcoming standard library additions">Review Queue</a></li>
        <li><a href="http://twitter.com/#search?q=%23d_lang" title="#d_lang on twitter.com">Twitter</a></li>
        <li><a href="http://digitalmars.com/d/dlinks.html" title="External D related links">Links</a></li>
        
</ul>
    </div>
  
<div id="translate" class="tool">Translate this page:
        <div id="google_translate_element"></div><script type="text/javascript">
        function googleTranslateElementInit() {
          new google.translate.TranslateElement({
            pageLanguage: 'en',
            autoDisplay: false,
            layout: google.translate.TranslateElement.InlineLayout.SIMPLE
          }, 'google_translate_element');
        }
        </script>
<script type="text/javascript" src="http://translate.google.com/translate_a/element.js?cb=googleTranslateElementInit"></script>
</div>
</div>
<div id="twitter">
<script src="http://widgets.twimg.com/j/2/widget.js"></script>
<script>
new TWTR.Widget({
  version : 2,
  type : 'profile',
  rpp : 8,
  interval : 30000,
  width : 'auto',
  height : 600,
  theme : {
    shell : {
      background : '#1f252b',
      //color : '#000000'
    },
    tweets : {
      //background : '',
      //color : '',
      //links : ''
    }
  },
  features : {
    scrollbar : true,
    loop : false,
    live : true,
    behavior : 'all'
  }
}).render().setUser('D_programming').start();
</script>
</div>

<div id="content" style="margin-right:18em;" class='hyphenate'>

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
