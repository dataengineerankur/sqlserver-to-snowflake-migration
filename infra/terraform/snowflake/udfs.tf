locals {
  fn_format_money_body = <<-SQL
    '$' || TO_VARCHAR(AMOUNT, '999,999,999,990.00')
  SQL

  fn_order_line_count_body = <<-SQL
    SELECT COUNT_BIG(*)
    FROM ${var.database_name}.BRONZE.ORDER_ITEMS
    WHERE ORDER_ID = P_ORDER_ID
  SQL

  sp_xml_order_document_body = <<-PYEOF
import xml.etree.ElementTree as ET
from xml.dom.minidom import parseString


def run(session, p_order_id: float) -> str:
    order_id = int(p_order_id)

    order_rows = session.sql(
        f"""
        SELECT o.ORDER_ID, o.ORDER_DATE::VARCHAR AS ORDER_DATE,
               o.STATUS, o.TOTAL_AMOUNT,
               c.CUSTOMER_CODE, c.FULL_NAME, c.COUNTRY
        FROM BRONZE.ORDERS o
        JOIN BRONZE.CUSTOMERS c ON c.CUSTOMER_ID = o.CUSTOMER_ID
        WHERE o.ORDER_ID = {order_id}
        """
    ).collect()

    if not order_rows:
        return '<OrderBundle/>'

    row = order_rows[0]
    bundle = ET.Element('OrderBundle')
    order_el = ET.SubElement(bundle, 'Order')
    ET.SubElement(order_el, 'OrderId').text    = str(row['ORDER_ID'])
    ET.SubElement(order_el, 'OrderDate').text  = row['ORDER_DATE']
    ET.SubElement(order_el, 'Status').text     = row['STATUS']
    ET.SubElement(order_el, 'TotalAmount').text = str(row['TOTAL_AMOUNT'])

    cust = ET.SubElement(order_el, 'Customer')
    ET.SubElement(cust, 'CustomerCode').text = row['CUSTOMER_CODE']
    ET.SubElement(cust, 'FullName').text     = row['FULL_NAME']
    ET.SubElement(cust, 'Country').text      = row['COUNTRY']

    line_rows = session.sql(
        f"""
        SELECT oi.ORDER_ITEM_ID, oi.QUANTITY, oi.UNIT_PRICE, oi.LINE_TOTAL,
               p.SKU, p.PRODUCT_NAME
        FROM BRONZE.ORDER_ITEMS oi
        JOIN BRONZE.PRODUCTS p ON p.PRODUCT_ID = oi.PRODUCT_ID
        WHERE oi.ORDER_ID = {order_id}
        """
    ).collect()

    for line in line_rows:
        line_el = ET.SubElement(order_el, 'Line')
        ET.SubElement(line_el, 'OrderItemId').text = str(line['ORDER_ITEM_ID'])
        ET.SubElement(line_el, 'Quantity').text    = str(line['QUANTITY'])
        ET.SubElement(line_el, 'UnitPrice').text   = str(line['UNIT_PRICE'])
        ET.SubElement(line_el, 'LineTotal').text   = str(line['LINE_TOTAL'])
        ET.SubElement(line_el, 'SKU').text         = line['SKU']

    raw = ET.tostring(bundle, encoding='unicode')
    return parseString(raw).toprettyxml(indent='  ')
  PYEOF

  sp_inv_stock_xml_body = <<-PYEOF
import xml.etree.ElementTree as ET
from xml.dom.minidom import parseString


def run(session, p_wh_id: float) -> str:
    wh_id = int(p_wh_id)

    rows = session.sql(
        f"""
        SELECT w.WH_CODE, s.SKU_CODE, m.QTY_CHANGE, m.REASON
        FROM BRONZE.INV_STOCK_MOVEMENTS m
        JOIN BRONZE.INV_WAREHOUSES w ON w.WH_ID = m.WH_ID
        JOIN BRONZE.INV_SKU s ON s.SKU_ID = m.SKU_ID
        WHERE m.WH_ID = {wh_id}
        """
    ).collect()

    wh_el = ET.Element('Warehouse')
    for row in rows:
        move = ET.SubElement(wh_el, 'Move')
        ET.SubElement(move, 'WhCode').text    = row['WH_CODE']
        ET.SubElement(move, 'SkuCode').text   = row['SKU_CODE']
        ET.SubElement(move, 'QtyChange').text = str(row['QTY_CHANGE'])
        ET.SubElement(move, 'Reason').text    = row['REASON'] or ''

    raw = ET.tostring(wh_el, encoding='unicode')
    return parseString(raw).toprettyxml(indent='  ')
  PYEOF
}

resource "snowflake_function_sql" "fn_format_money" {
  database = var.database_name
  schema   = "BRONZE"
  name     = "FN_FORMAT_MONEY"

  arguments {
    name = "AMOUNT"
    type = "NUMBER"
  }
  return_type   = "VARCHAR"
  function_body = local.fn_format_money_body

  depends_on = [snowflake_schema.bronze]
}

resource "snowflake_function_sql" "fn_order_line_count" {
  database = var.database_name
  schema   = "BRONZE"
  name     = "FN_ORDER_LINE_COUNT"

  arguments {
    name = "P_ORDER_ID"
    type = "NUMBER"
  }
  return_type   = "NUMBER"
  function_body = local.fn_order_line_count_body

  depends_on = [snowflake_schema.bronze]
}

resource "snowflake_procedure_python" "sp_xml_order_document" {
  database = var.database_name
  schema   = "BRONZE"
  name     = "SP_XML_ORDER_DOCUMENT"

  runtime_version = "3.11"
  packages        = ["snowflake-snowpark-python"]
  handler         = "run"
  return_type     = "VARCHAR"

  arguments {
    name = "P_ORDER_ID"
    type = "FLOAT"
  }

  procedure_body = local.sp_xml_order_document_body

  depends_on = [snowflake_schema.bronze]
}

resource "snowflake_procedure_python" "sp_inv_stock_xml" {
  database = var.database_name
  schema   = "BRONZE"
  name     = "SP_INV_STOCK_XML"

  runtime_version = "3.11"
  packages        = ["snowflake-snowpark-python"]
  handler         = "run"
  return_type     = "VARCHAR"

  arguments {
    name = "P_WH_ID"
    type = "FLOAT"
  }

  procedure_body = local.sp_inv_stock_xml_body

  depends_on = [snowflake_schema.bronze]
}
