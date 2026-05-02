"""
Glue job: copy raw files from a source datalake bucket into the DMS landing bucket.
Only used when enable_datalake_ingest = true in Terraform.
"""
import sys
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job

args = getResolvedOptions(sys.argv, ["JOB_NAME", "SOURCE_BUCKET", "SOURCE_PREFIX", "TARGET_BUCKET", "RAW_PREFIX"])
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args["JOB_NAME"], args)

source_path = f"s3://{args['SOURCE_BUCKET']}/{args['SOURCE_PREFIX']}"
target_path = f"s3://{args['TARGET_BUCKET']}/{args['RAW_PREFIX']}/"

df = spark.read.parquet(source_path)
df.write.mode("append").parquet(target_path)
job.commit()
