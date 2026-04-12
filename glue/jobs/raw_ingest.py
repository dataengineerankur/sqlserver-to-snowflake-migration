import sys

import boto3
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext

args = getResolvedOptions(
    sys.argv,
    [
        "JOB_NAME",
        "TARGET_BUCKET",
        "RAW_PREFIX",
    ],
)

try:
    optional_args = getResolvedOptions(sys.argv, ["SOURCE_BUCKET", "SOURCE_PREFIX"])
    args.update(optional_args)
except Exception:
    pass

sc = SparkContext.getOrCreate()
glue_context = GlueContext(sc)
job = Job(glue_context)
job.init(args["JOB_NAME"], args)

source_bucket = args.get("SOURCE_BUCKET", args["TARGET_BUCKET"])
source_prefix = args.get("SOURCE_PREFIX", "dms-source").rstrip("/")
target_bucket = args["TARGET_BUCKET"]
raw_prefix = args["RAW_PREFIX"].rstrip("/")

s3 = boto3.client("s3")

source_prefix = source_prefix + "/" if source_prefix else ""
raw_prefix = raw_prefix + "/" if raw_prefix else ""

paginator = s3.get_paginator("list_objects_v2")
copied = 0
valid_tables = {"customers", "products", "orders", "order_items"}


def delete_prefix(bucket, prefix):
    keys = []
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for obj in page.get("Contents", []):
            keys.append({"Key": obj["Key"]})
            if len(keys) == 1000:
                s3.delete_objects(Bucket=bucket, Delete={"Objects": keys})
                keys = []
    if keys:
        s3.delete_objects(Bucket=bucket, Delete={"Objects": keys})


# Keep bronze layer clean from old buggy runs.
for stale in ["sales/", "awsdms_history/", "awsdms_status/", "awsdms_suspended_tables/"]:
    delete_prefix(target_bucket, f"{raw_prefix}{stale}")

for page in paginator.paginate(Bucket=source_bucket, Prefix=source_prefix):
    for obj in page.get("Contents", []):
        key = obj["Key"]
        if key.endswith("/"):
            continue
        relative_key = key[len(source_prefix) :] if source_prefix else key
        if relative_key.startswith("sales/"):
            relative_key = relative_key[len("sales/") :]
        parts = relative_key.split("/", 1)
        if not parts or parts[0] not in valid_tables:
            continue
        target_key = f"{raw_prefix}{relative_key}"
        s3.copy_object(
            Bucket=target_bucket,
            Key=target_key,
            CopySource={"Bucket": source_bucket, "Key": key},
        )
        copied += 1

if copied == 0:
    raise RuntimeError(f"No objects found under s3://{source_bucket}/{source_prefix}")

job.commit()
