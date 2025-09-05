CREATE SEQUENCE seq_audit_id START WITH 1 INCREMENT BY 1;

CREATE OR REPLACE TRIGGER trg_inventory_audit
AFTER INSERT OR UPDATE OR DELETE
ON INVENTORY_MASTER
FOR EACH ROW
DECLARE
    v_old_values   CLOB;
    v_new_values   CLOB;
    v_role         VARCHAR2(20);
    v_operation    VARCHAR2(20);
    v_errmsg       VARCHAR2(4000);  
BEGIN
    -- Default role (current DB user)
    v_role := SYS_CONTEXT('USERENV', 'SESSION_USER');

    -- Operation type
    IF INSERTING THEN
        v_operation := 'INSERT';
    ELSIF UPDATING THEN
        v_operation := 'UPDATE';
    ELSIF DELETING THEN
        v_operation := 'DELETE';
    END IF;

    -- Build OLD values (for UPDATE/DELETE)
    IF UPDATING OR DELETING THEN
        v_old_values := 'Inventory_ID=' || :OLD.inventory_id ||
                        ', Product_ID='   || :OLD.product_id ||
                        ', Location_ID='  || :OLD.location_id ||
                        ', Current_Stock='|| :OLD.current_stock ||
                        ', Reorder_Level='|| :OLD.reorder_level ||
                        ', Max_Stock='    || :OLD.max_stock_level ||
                        ', Safety_Stock=' || :OLD.safety_stock ||
                        ', Last_Move='    || TO_CHAR(:OLD.last_movement_date, 'YYYY-MM-DD HH24:MI:SS') ||
                        ', Unit_Cost='    || :OLD.unit_cost;
    END IF;

    -- Build NEW values (for INSERT/UPDATE)
    IF INSERTING OR UPDATING THEN
        v_new_values := 'Inventory_ID=' || :NEW.inventory_id ||
                        ', Product_ID='   || :NEW.product_id ||
                        ', Location_ID='  || :NEW.location_id ||
                        ', Current_Stock='|| :NEW.current_stock ||
                        ', Reorder_Level='|| :NEW.reorder_level ||
                        ', Max_Stock='    || :NEW.max_stock_level ||
                        ', Safety_Stock=' || :NEW.safety_stock ||
                        ', Last_Move='    || TO_CHAR(:NEW.last_movement_date, 'YYYY-MM-DD HH24:MI:SS') ||
                        ', Unit_Cost='    || :NEW.unit_cost;
    END IF;

    -- Insert into Audit Trail
    INSERT INTO AUDIT_TRAIL (
        AUDIT_ID, TABLE_NAME, OPERATION_TYPE, OLD_VALUES, NEW_VALUES, CHANGED_BY, CHANGE_DATE
    ) VALUES (
        seq_audit_id.NEXTVAL,
        'INVENTORY_MASTER',
        v_operation,
        v_old_values,
        v_new_values,
        v_role,
        SYSDATE
    );

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('TRIGGER ERROR: No data found while auditing.');

    WHEN DUP_VAL_ON_INDEX THEN
        DBMS_OUTPUT.PUT_LINE('TRIGGER ERROR: Duplicate audit ID.');

    WHEN OTHERS THEN
        BEGIN
            v_errmsg := SUBSTR('TRIGGER_ERROR: ' || SQLERRM, 1, 200); 

            INSERT INTO AUDIT_TRAIL (
                AUDIT_ID, TABLE_NAME, OPERATION_TYPE, OLD_VALUES, NEW_VALUES, CHANGED_BY, CHANGE_DATE
            ) VALUES (
                seq_audit_id.NEXTVAL,
                'INVENTORY_MASTER',
                'ERROR',
                NULL,
                NULL,
                v_errmsg,   
                SYSDATE
            );
        EXCEPTION
            WHEN OTHERS THEN
                NULL; 
        END;
END;

SELECT trigger_name, status 
    FROM user_triggers
WHERE trigger_name = 'TRG_INVENTORY_AUDIT';
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Trigger Name : TRG_UPDATE_LAST_MOVEMENT
-- Table        : INVENTORY_MASTER
-- Timing       : BEFORE UPDATE OF (CURRENT_STOCK, UNIT_COST)
-- Purpose      : 
--   Ensures that whenever CURRENT_STOCK or UNIT_COST is modified,
--   the LAST_MOVEMENT_DATE column is automatically refreshed with
--   the current system date/time (SYSDATE).
--
-- Business Rule :
--   1. LAST_MOVEMENT_DATE must always reflect the most recent change 
--      in stock levels or unit cost.
--
-- Error Handling :

--   - Errors are re-raised using RAISE_APPLICATION_ERROR with code -20001.
--   - The raised error includes the trigger name and Oracle's original 
--     error message for easier debugging and logging.
------------------------------------------------------

CREATE OR REPLACE TRIGGER trg_update_last_movement
BEFORE UPDATE OF current_stock, unit_cost 
ON inventory_master
FOR EACH ROW
DECLARE
    v_errmsg VARCHAR2(4000); -- Holds detailed Oracle error message
BEGIN
    --------------------------------------------------------------------------
    -- Main Logic
    -- If either CURRENT_STOCK or UNIT_COST is updated, 
    -- refresh LAST_MOVEMENT_DATE to current system date.
    --------------------------------------------------------------------------
    :NEW.last_movement_date := SYSDATE;

EXCEPTION
    
    WHEN OTHERS THEN
        v_errmsg := SQLERRM; -- Get exact Oracle error message
        RAISE_APPLICATION_ERROR(
            -20001, 
            'TRG_UPDATE_LAST_MOVEMENT failed: ' || v_errmsg
        );
END;
/
------------------------------------------------------------------------------------------------------------

------------------------------------------------------------------------------
-- Trigger Name   : trg_validate_stock_quantities
-- Table Name     : inventory_master
-- Event          : BEFORE INSERT OR UPDATE OF 
--                  (current_stock, reorder_level, max_stock_level, safety_stock)
-- Purpose        : Enforce data integrity and business rules on stock fields.
--
-- Key Rules Enforced:
--   1. Prevent negative values for stock quantities.
--   2. Enforce logical hierarchy between stock levels:
--        - safety_stock <= reorder_level <= max_stock_level
--        - current_stock <= max_stock_level
--   3. Disallow NULL values for stock-related fields (if business requires).
--
-- Error Handling:
--   - Each violation raises a unique Oracle error (-20001 to -20008)
--     with a clear business-friendly message.
--   - Unexpected errors are caught in a generic handler (-20999)
--     for easier debugging and support.
--

------------------------------------------------------------------------------

CREATE OR REPLACE TRIGGER trg_validate_stock_quantities
BEFORE INSERT OR UPDATE OF current_stock, reorder_level, max_stock_level, safety_stock
ON inventory_master
FOR EACH ROW
DECLARE
BEGIN
    -------------------------------------------------------------------------
    -- Validation 1: Prevent negative values
    -------------------------------------------------------------------------
    IF :NEW.current_stock < 0 THEN
        RAISE_APPLICATION_ERROR(-20001, 'Current stock cannot be negative.');
    END IF;

    IF :NEW.reorder_level < 0 THEN
        RAISE_APPLICATION_ERROR(-20002, 'Reorder level cannot be negative.');
    END IF;

    IF :NEW.max_stock_level < 0 THEN
        RAISE_APPLICATION_ERROR(-20003, 'Maximum stock level cannot be negative.');
    END IF;

    IF :NEW.safety_stock < 0 THEN
        RAISE_APPLICATION_ERROR(-20004, 'Safety stock cannot be negative.');
    END IF;

    -------------------------------------------------------------------------
    -- Validation 2: Enforce logical business rules
    -------------------------------------------------------------------------
    -- Rule: Safety stock must not exceed reorder level
    IF :NEW.safety_stock > :NEW.reorder_level THEN
        RAISE_APPLICATION_ERROR(-20005, 'Safety stock must not exceed reorder level.');
    END IF;

    -- Rule: Reorder level must not exceed maximum stock level
    IF :NEW.reorder_level > :NEW.max_stock_level THEN
        RAISE_APPLICATION_ERROR(-20006, 'Reorder level cannot exceed maximum stock level.');
    END IF;

    -- Rule: Current stock must not exceed maximum stock capacity
    IF :NEW.current_stock > :NEW.max_stock_level THEN
        RAISE_APPLICATION_ERROR(-20007, 'Current stock cannot exceed maximum stock level.');
    END IF;

EXCEPTION

    WHEN OTHERS THEN
        RAISE_APPLICATION_ERROR(
            -20999, 
            'Unexpected error in trg_validate_stock_quantities: ' || SQLERRM
        );
END;
/
---------------------
ALTER TRIGGER trg_update_last_movement DISABLE;
ALTER TRIGGER trg_validate_stock_quantities DISABLE;
ALTER TRIGGER trg_inventory_audit DISABLE;
-------------
ALTER TRIGGER trg_update_last_movement ENABLE;
ALTER TRIGGER trg_validate_stock_quantities ENABLE;
ALTER TRIGGER trg_another_trigger ENABLE;

select * from stock_transfers;

SELECT trigger_name, table_name, status, triggering_event, trigger_type
FROM user_triggers
ORDER BY table_name, trigger_name;



