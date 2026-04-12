import sys
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from pyspark.sql import functions as F

args = getResolvedOptions(
    sys.argv,
    [
        "JOB_NAME",
        "S3_BUCKET",
    ],
)

sc = SparkContext.getOrCreate()
glue_context = GlueContext(sc)
spark = glue_context.spark_session
job = Job(glue_context)
job.init(args["JOB_NAME"], args)

bucket = args["S3_BUCKET"]

def read_silver(table):
    return spark.read.parquet(f"s3://{bucket}/glue/silver/{table}/")

customers = read_silver("stg_customers")
products = read_silver("stg_products")
orders = read_silver("stg_orders")
order_items = read_silver("stg_order_items")

dim_customers = customers.select(
    "customer_id", "first_name", "last_name", "email", "created_at", "updated_at"
)

dim_products = products.select(
    "product_id", "sku", "product_name", "category", "price", "created_at", "updated_at"
)

items_agg = (
    order_items.groupBy("order_id")
    .agg(
        F.sum("quantity").alias("total_items"),
        F.sum("line_total").alias("gross_revenue"),
        F.max("updated_at").alias("items_updated_at"),
    )
)

fct_orders = (
    orders.join(items_agg, "order_id", "left")
    .select(
        orders.order_id,
        orders.customer_id,
        orders.order_status,
        orders.order_date,
        orders.updated_at.alias("order_updated_at"),
        F.coalesce(items_agg.total_items, F.lit(0)).alias("total_items"),
        F.coalesce(items_agg.gross_revenue, F.lit(0)).alias("gross_revenue"),
    )
)

def write_s3(df, name):
    df.write.mode("overwrite").parquet(f"s3://{bucket}/glue/gold/{name}/")

write_s3(dim_customers, "dim_customers")
write_s3(dim_products, "dim_products")
write_s3(fct_orders, "fct_orders")

job.commit()
