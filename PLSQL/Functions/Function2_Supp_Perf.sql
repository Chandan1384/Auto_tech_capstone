CREATE OR REPLACE FUNCTION Fn_SUPPLIER_PERFORMANCE(
    p_supplier_id     IN VARCHAR2,
    p_quality_weight  IN NUMBER DEFAULT 0.7,
    p_delivery_weight IN NUMBER DEFAULT 0.3
) RETURN NUMBER IS
    v_avg_quality       NUMBER := 0;
    v_total_delivered   NUMBER := 0;
    v_total_rejected    NUMBER := 0;
    v_delivery_rating   NUMBER := 0;
    v_final_rating      NUMBER := 0;

    -- Custom exception for invalid supplier
    ex_invalid_supplier EXCEPTION;
BEGIN
    -- Validate input supplier ID
    IF p_supplier_id IS NULL THEN
        RAISE ex_invalid_supplier;
    END IF;

    -- Step 1: Aggregate quality rating
    SELECT AVG(NVL(QUALITY_RATING,0))
    INTO v_avg_quality
    FROM SUPPLIER_PERFORMANCE
    WHERE SUPPLIER_ID = p_supplier_id;

    -- Step 2: Aggregate delivered and rejected quantities
    SELECT SUM(NVL(QUANTITY_DELIVERED,0)),
           SUM(NVL(QUANTITY_REJECTED,0))
    INTO v_total_delivered, v_total_rejected
    FROM SUPPLIER_PERFORMANCE
    WHERE SUPPLIER_ID = p_supplier_id;

    -- Step 3: Calculate delivery rating
    IF v_total_delivered > 0 THEN
        v_delivery_rating := ((v_total_delivered - v_total_rejected) / v_total_delivered) * 5;
    ELSE
        v_delivery_rating := 0;
    END IF;

    -- Step 4: Weighted final rating
    v_final_rating := NVL(v_avg_quality,0) * p_quality_weight +
                      v_delivery_rating * p_delivery_weight;

    IF v_final_rating > 5 THEN
        v_final_rating := 5;
    ELSIF v_final_rating < 0 THEN
        v_final_rating := 0;
    END IF;

    RETURN ROUND(v_final_rating,2);

EXCEPTION
    WHEN ex_invalid_supplier THEN
        DBMS_OUTPUT.PUT_LINE('ERROR: Supplier ID cannot be NULL.');
        RETURN NULL;

    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('WARNING: No performance records found for supplier ' || p_supplier_id);
        RETURN NULL;

    WHEN VALUE_ERROR THEN
        DBMS_OUTPUT.PUT_LINE('ERROR: Invalid numeric value encountered.');
        RETURN NULL;

    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Unexpected error: ' || SQLERRM);
        RETURN NULL;
END Fn_SUPPLIER_PERFORMANCE;
/


SELECT AUTOMOTIVE_APP.Fn_SUPPLIER_PERFORMANCE('KG-CN-21') AS SUPPLIER_RATING
FROM DUAL;
