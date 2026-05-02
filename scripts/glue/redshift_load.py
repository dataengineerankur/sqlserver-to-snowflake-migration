"""
Glue job: load DMS Parquet files from S3 into Redshift.
Only used when enable_redshift = true in Terraform.
"""
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job

args = getResolvedOptions(sys.argv, ["JOB_NAME", "S3_BUCKET", "REDSHIFT_SCHEMA", "REDSHIFT_CONNECTION_NAME"])
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args["JOB_NAME"], args)

s3_path = f"s3://{args['S3_BUCKET']}/dms/"
datasource = glueContext.create_dynamic_frame.from_options(
    connection_type="s3",
    connection_options={"path": s3_path, "recurse": True},
    format="parquet",
)
glueContext.write_dynamic_frame.from_jdbc_conf(
    frame=datasource,
    catalog_connection=args["REDSHIFT_CONNECTION_NAME"],
    connection_options={"dbtable": f"{args['REDSHIFT_SCHEMA']}.raw_dms", "database": "dev"},
)
job.commit()
