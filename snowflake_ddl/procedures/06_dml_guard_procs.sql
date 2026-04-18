USE DATABASE MSSQL_MIGRATION_LAB;
USE SCHEMA BRONZE;

-- SQL Server had INSTEAD OF triggers on views (tr_vw_Orders_Dml_IOD,
-- tr_vw_Orders_Dml_IOU, tr_vw_StockOrders_IOI). Snowflake has no trigger
-- concept at all, so the logic moves into stored procedures that callers
-- invoke directly instead of writing to a view.


CREATE OR REPLACE PROCEDURE BRONZE.SP_SOFT_DELETE_ORDER(P_ORDER_ID NUMBER)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    v_status VARCHAR;
BEGIN
    SELECT STATUS INTO v_status
    FROM BRONZE.ORDERS
    WHERE ORDER_ID = :P_ORDER_ID;

    IF (v_status IS NULL) THEN
        RETURN 'ERROR: order not found';
    END IF;

    IF (v_status = 'Closed') THEN
        RETURN 'ERROR: cannot delete closed orders (archive pattern)';
    END IF;

    INSERT INTO BRONZE.ORDERS_ARCHIVE
        (ORDER_ID, CUSTOMER_ID, ORDER_DATE, STATUS, TOTAL_AMOUNT, NOTES, ARCHIVE_REASON)
    SELECT ORDER_ID, CUSTOMER_ID, ORDER_DATE, STATUS, TOTAL_AMOUNT, NOTES,
           'SOFT DELETE via SP_SOFT_DELETE_ORDER'
    FROM BRONZE.ORDERS
    WHERE ORDER_ID = :P_ORDER_ID;

    DELETE FROM BRONZE.ORDERS WHERE ORDER_ID = :P_ORDER_ID;

    RETURN 'Archived and deleted order_id=' || P_ORDER_ID;
END;
$$;


CREATE OR REPLACE PROCEDURE BRONZE.SP_UPDATE_ORDER(
    P_ORDER_ID    NUMBER,
    P_STATUS      VARCHAR,
    P_NOTES       VARCHAR,
    P_TOTAL_AMOUNT NUMBER
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    v_exists NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_exists
    FROM BRONZE.ORDERS
    WHERE ORDER_ID = :P_ORDER_ID;

    IF (v_exists = 0) THEN
        RETURN 'ERROR: order not found';
    END IF;

    UPDATE BRONZE.ORDERS
    SET
        STATUS       = COALESCE(:P_STATUS,       STATUS),
        NOTES        = COALESCE(:P_NOTES,        NOTES),
        TOTAL_AMOUNT = COALESCE(:P_TOTAL_AMOUNT, TOTAL_AMOUNT)
    WHERE ORDER_ID = :P_ORDER_ID;

    RETURN 'Updated order_id=' || P_ORDER_ID;
END;
$$;
