Tool to pull list of files from the s3 downloads.dlang.org bucket
and generate the appropriate index.html pages to allow the
bucket to be used as a website.

It expects a config file in the form:

```
{
    "aws" : {
        "key"    : "<aws access key>",
        "secret" : "<aws secret key>",
        "endpoint" : "s3-us-west-2.amazonaws.com"
    },

    "s3bucket" : "downloads.dlang.org",

    "base_dir" : "/media/scratch/ddo-upload"
}
```

