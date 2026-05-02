"""
Glue job: build Gold Customers dimension from Silver layer.
"""
import sys
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job

args = getResolvedOptions(sys.argv, ["JOB_NAME", "S3_BUCKET", "SILVER_PREFIX", "GOLD_PREFIX"])
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args["JOB_NAME"], args)

silver_path = f"s3://{args['S3_BUCKET']}/{args['SILVER_PREFIX']}/customers/"
gold_path   = f"s3://{args['S3_BUCKET']}/{args['GOLD_PREFIX']}/dim_customers/"

df = spark.read.parquet(silver_path)
df.write.mode("overwrite").parquet(gold_path)
job.commit()
