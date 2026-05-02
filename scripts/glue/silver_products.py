"""
Glue job: transform raw Products Parquet into Silver layer.
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

raw_path    = f"s3://{args['S3_BUCKET']}/{args['RAW_PREFIX']}/dbo/Products/"
silver_path = f"s3://{args['S3_BUCKET']}/{args['SILVER_PREFIX']}/products/"

df = spark.read.parquet(raw_path)
df = df.dropDuplicates(["ProductID"])

df.write.mode("overwrite").parquet(silver_path)
job.commit()
