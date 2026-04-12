import sys
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from pyspark.sql import functions as F
from pyspark.sql.window import Window

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

today = F.date_format(F.current_date(), "yyyyMMdd")

def read_raw(table):
    return spark.read.parquet(f"s3://{bucket}/dms/sales/{table}/")

def dedupe_latest(df, key_col, ts_cols):
    order_cols = [F.col(c).desc_nulls_last() for c in ts_cols]
    w = Window.partitionBy(key_col).orderBy(*order_cols)
    return df.withColumn("rn", F.row_number().over(w)).filter(F.col("rn") == 1).drop("rn")

customers = read_raw("customers").filter((F.col("dms_op").isNull()) | (F.col("dms_op") != "D"))
customers = dedupe_latest(customers, "customer_id", ["dms_commit_ts", "updated_at", "created_at"])
customers = customers.withColumn("load_dt", today)

products = read_raw("products").filter((F.col("dms_op").isNull()) | (F.col("dms_op") != "D"))
products = dedupe_latest(products, "product_id", ["dms_commit_ts", "updated_at", "created_at"])
products = products.withColumn("load_dt", today)

orders = read_raw("orders").filter((F.col("dms_op").isNull()) | (F.col("dms_op") != "D"))
orders = dedupe_latest(orders, "order_id", ["dms_commit_ts", "updated_at", "order_date"])
orders = orders.withColumn("load_dt", today)

order_items = read_raw("order_items").filter((F.col("dms_op").isNull()) | (F.col("dms_op") != "D"))
order_items = dedupe_latest(order_items, "order_item_id", ["dms_commit_ts", "updated_at", "created_at"])
order_items = order_items.withColumn("line_total", F.col("quantity") * F.col("unit_price")).withColumn("load_dt", today)

def write_s3(df, name):
    df.write.mode("overwrite").parquet(f"s3://{bucket}/glue/silver/{name}/")

write_s3(customers, "stg_customers")
write_s3(products, "stg_products")
write_s3(orders, "stg_orders")
write_s3(order_items, "stg_order_items")

job.commit()
