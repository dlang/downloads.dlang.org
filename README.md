Tool to pull list of files from the s3 downloads.dlang.org bucket
and generate the appropriate index.html pages to allow the
bucket to be used as a website.

It expects a `config.json` file in the form:

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

How to build
----------

```
make
```

How to build
----------

```
./src/build-gen-index <command>
```

Available commands:
- `s3_index`: generate an index file of all files in the S3 bucket
- `folder_index <folder>`: generate an index file of all files in a local folder
- `generate`: generate the HTML index pages

Multiple commands can be combined

```
./src/build-gen-index s3_index generate
```

How to deploy
-------------

`sync-ddo` will generate the index and HTML files and deploy them to the S3 bucket:

```
./sync-ddo
```

If you deploy manually, make sure to generate an up-to-date index file (`s3_index` or `folder_index`) and respective HTML files before.
