
-- Create sequence in AUTOMOTIVE_APP
CREATE SEQUENCE AUTOMOTIVE_APP.STOCK_TRANSFER_SEQ
    START WITH 1
    INCREMENT BY 1;

-- Procedure under AUTOMOTIVE_APP
CREATE OR REPLACE PROCEDURE AUTOMOTIVE_APP.TRANSFER_STOCK (
    p_product_id    IN VARCHAR2,
    p_from_location IN VARCHAR2,
    p_to_location   IN VARCHAR2,
    p_quantity      IN NUMBER,
    p_approved_by   IN VARCHAR2 DEFAULT 'MANAGER',
    p_status        IN VARCHAR2 DEFAULT 'PENDING'
) IS
    v_stock_available NUMBER;
    v_exists_dest     NUMBER;
    v_exists_from     NUMBER;
    v_transfer_id     VARCHAR2(30);
BEGIN
    -- Generate unique transfer ID using sequence
    v_transfer_id := 'TR' || LPAD(AUTOMOTIVE_APP.STOCK_TRANSFER_SEQ.NEXTVAL, 6, '0');

    -- Validate different locations
    IF p_from_location = p_to_location THEN
        RAISE_APPLICATION_ERROR(-20001, 'FROM and TO locations cannot be the same.');
    END IF;

    -- Validate positive quantity
    IF p_quantity <= 0 THEN
        RAISE_APPLICATION_ERROR(-20002, 'Quantity must be positive.');
    END IF;

    -- Check source location exists
    SELECT COUNT(*) INTO v_exists_from
    FROM AUTOMOTIVE_APP.INVENTORY_MASTER
    WHERE PRODUCT_ID = p_product_id
      AND LOCATION_ID = p_from_location;

    IF v_exists_from = 0 THEN
        RAISE_APPLICATION_ERROR(-20007, 'Product not found at FROM_LOCATION.');
    END IF;

    -- Check destination location exists
    SELECT COUNT(*) INTO v_exists_dest
    FROM AUTOMOTIVE_APP.INVENTORY_MASTER
    WHERE PRODUCT_ID = p_product_id
      AND LOCATION_ID = p_to_location;

    IF v_exists_dest = 0 THEN
        RAISE_APPLICATION_ERROR(-20008, 'Product not found at TO_LOCATION.');
    END IF;

    -- Check stock at source
    SELECT CURRENT_STOCK INTO v_stock_available
    FROM AUTOMOTIVE_APP.INVENTORY_MASTER
    WHERE PRODUCT_ID = p_product_id
      AND LOCATION_ID = p_from_location;

    IF p_quantity > v_stock_available THEN
        RAISE_APPLICATION_ERROR(-20003, 'Quantity exceeds available stock at source.');
    END IF;

    -- Deduct from source
    UPDATE AUTOMOTIVE_APP.INVENTORY_MASTER
    SET CURRENT_STOCK = CURRENT_STOCK - p_quantity
    WHERE PRODUCT_ID = p_product_id
      AND LOCATION_ID = p_from_location;

    -- Add to destination
    UPDATE AUTOMOTIVE_APP.INVENTORY_MASTER
    SET CURRENT_STOCK = CURRENT_STOCK + p_quantity
    WHERE PRODUCT_ID = p_product_id
      AND LOCATION_ID = p_to_location;

    -- Insert transfer record
    INSERT INTO AUTOMOTIVE_APP.STOCK_TRANSFERS (
        TRANSFER_ID, PRODUCT_ID, FROM_LOCATION, TO_LOCATION, TRANS_QUANTITY,
        TRANSFER_DATE, APPROVED_BY, STATUS
    ) VALUES (
        v_transfer_id, p_product_id, p_from_location, p_to_location,
        p_quantity, SYSDATE, p_approved_by, p_status
    );

    COMMIT;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        ROLLBACK;
        RAISE_APPLICATION_ERROR(-20005, 'Product or location not found.');
    WHEN VALUE_ERROR THEN
        ROLLBACK;
        RAISE_APPLICATION_ERROR(-20009, 'Invalid numeric value provided.');
    WHEN DUP_VAL_ON_INDEX THEN
        ROLLBACK;
        RAISE_APPLICATION_ERROR(-20010, 'Duplicate transfer ID encountered.');
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE_APPLICATION_ERROR(-20006, 'Unexpected error: ' || SQLERRM);
END;
/


commit;

BEGIN
    AUTOMOTIVE_APP.TRANSFER_STOCK(
        p_product_id    => 'ELE-VEC-9675',
        p_from_location => 'BNG-IN-91',
        p_to_location   => 'KAN-USA-1',
        p_quantity      => 1
    );
END;

SELECT *
FROM AUTOMOTIVE_APP.STOCK_TRANSFERS
WHERE PRODUCT_ID = 'ELE-VEC-9675'
ORDER BY TRANSFER_DATE DESC;


select * from supplier_performance;