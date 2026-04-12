"""
AWS Glue job: SQL Server JDBC → partitioned Parquet on the Glue-only S3 bucket.

Glue job parameters:
  JOB_NAME, MSSQL_HOST, MSSQL_USER, MSSQL_PASSWORD, MSSQL_DATABASE,
  TABLE_SCHEMA, TABLE_NAME, GLUE_S3_BUCKET
Optional: MSSQL_PORT (1433), NUM_PARTITIONS (4), PARTITION_COLUMN (numeric PK)

Incremental (optional): INCREMENTAL_COLUMN — monotonic column (PK or rowversion surrogate).
  Stores last max in s3://<bucket>/glue/mssql/_watermarks/<db>/<schema>_<table>.json
  via boto3; appends Parquet partitions each run (not full overwrite).
"""
import json
import sys

import boto3
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from botocore.exceptions import ClientError
from pyspark.sql import functions as F

args = getResolvedOptions(
    sys.argv,
    [
        "JOB_NAME",
        "MSSQL_HOST",
        "MSSQL_USER",
        "MSSQL_PASSWORD",
        "MSSQL_DATABASE",
        "GLUE_S3_BUCKET",
        "TABLE_SCHEMA",
        "TABLE_NAME",
    ],
)
extras = {}
for flag in ("MSSQL_PORT", "PARTITION_COLUMN", "NUM_PARTITIONS", "INCREMENTAL_COLUMN"):
    if f"--{flag}" in sys.argv:
        extras.update(getResolvedOptions(sys.argv, [flag]))

sc = SparkContext()
glue = GlueContext(sc)
spark = glue.spark_session
job = Job(glue)
job.init(args["JOB_NAME"], args)

port = extras.get("MSSQL_PORT", "1433")
host = args["MSSQL_HOST"]
db = args["MSSQL_DATABASE"]
schema = args["TABLE_SCHEMA"]
table = args["TABLE_NAME"]
bucket = args["GLUE_S3_BUCKET"].replace("s3://", "").rstrip("/").split("/")[0]

jdbc_url = (
    f"jdbc:sqlserver://{host}:{port};databaseName={db};encrypt=true;trustServerCertificate=true"
)

full_table = f"[{schema}].[{table}]"
reader = (
    spark.read.format("jdbc")
    .option("url", jdbc_url)
    .option("dbtable", full_table)
    .option("user", args["MSSQL_USER"])
    .option("password", args["MSSQL_PASSWORD"])
)

part_col = extras.get("PARTITION_COLUMN")
num_parts = int(extras.get("NUM_PARTITIONS", "4"))
if part_col:
    reader = (
        reader.option("partitionColumn", part_col)
        .option("lowerBound", "1")
        .option("upperBound", "1000000")
        .option("numPartitions", str(num_parts))
    )

df = reader.load()
incr_col = extras.get("INCREMENTAL_COLUMN")
watermark_key = f"glue/mssql/_watermarks/{db}/{schema}_{table}.json"
s3_client = boto3.client("s3")

def _read_watermark():
    try:
        r = s3_client.get_object(Bucket=bucket, Key=watermark_key)
        return json.loads(r["Body"].read()).get("last_max")
    except ClientError as e:
        if e.response["Error"]["Code"] in ("NoSuchKey", "404"):
            return None
        raise


def _write_watermark(last_max):
    body = json.dumps({"last_max": last_max}).encode("utf-8")
    s3_client.put_object(Bucket=bucket, Key=watermark_key, Body=body)


if incr_col:
    last_max = _read_watermark()
    if last_max is not None:
        df = df.filter(F.col(incr_col) > F.lit(last_max))

df = df.withColumn("ingest_date", F.date_format(F.current_timestamp(), "yyyy-MM-dd"))

out_path = f"s3://{bucket}/glue/mssql/{db}/{schema}_{table}/"
write_mode = "append" if incr_col else "overwrite"
df.write.mode(write_mode).partitionBy("ingest_date").parquet(out_path)

if incr_col:
    row = df.agg(F.max(F.col(incr_col)).alias("m")).collect()[0]
    agg = row["m"]
    if agg is not None:
        new_max = agg.isoformat() if hasattr(agg, "isoformat") else agg
        _write_watermark(new_max)

job.commit()
