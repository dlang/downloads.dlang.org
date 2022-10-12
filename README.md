Tool to pull list of files from the s3 downloads-dlang-org bucket
and generate the appropriate index.html pages to allow the
bucket to be used as a website.

Loads aws credentials and default region from ~/.aws/credentials and
~/.aws/config, i.e. where the aws-cli stores it's information.
See [Named Profiles - AWS Command Line Interface](https://docs.aws.amazon.com/cli/latest/userguide/cli-multiple-profiles.html) for more info.

How to build
----------

```
make
```

How to generate
----------

```
./src/build-gen-index --help
./src/build-gen-index --command <command>
```

Available commands:
- `s3_index`: generate an index file of all files in the S3 bucket
- `folder_index <folder>`: generate an index file of all files in a local folder
- `generate`: generate the HTML index pages

Multiple commands can be combined
```
./src/build-gen-index --command s3_index --command generate
```

How to deploy
-------------

`sync-ddo` will generate the index and HTML files and deploy them to the S3 bucket:

```
./sync-ddo
```

If you deploy manually, make sure to generate an up-to-date index file (`s3_index` or `folder_index`) and respective HTML files before.
