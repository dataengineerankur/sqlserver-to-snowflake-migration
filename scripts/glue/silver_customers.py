"""
Glue job: transform raw Customers Parquet into Silver layer.
Reads from S3 RAW_PREFIX, deduplicates by customer_id, writes to SILVER_PREFIX.
"""
import sys
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job

args = getResolvedOptions(sys.argv, ["JOB_NAME", "S3_BUCKET", "RAW_PREFIX", "SILVER_PREFIX"])
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args["JOB_NAME"], args)

raw_path    = f"s3://{args['S3_BUCKET']}/{args['RAW_PREFIX']}/dbo/Customers/"
silver_path = f"s3://{args['S3_BUCKET']}/{args['SILVER_PREFIX']}/customers/"

df = spark.read.parquet(raw_path)
df = df.dropDuplicates(["CustomerID"])

df.write.mode("overwrite").parquet(silver_path)
job.commit()
