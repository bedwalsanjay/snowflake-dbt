{{ config(
    materialized='incremental',
    unique_key='order_item_id'
) }}

WITH order_items AS (
    SELECT * FROM {{ ref('stg_order_items') }}
),

orders AS (
    SELECT * FROM {{ ref('stg_orders') }}
),

final AS (
    SELECT
        -- Transaction identifiers
        oi.order_item_id,
        oi.order_item_order_id                          AS order_id,
        o.order_date,
        CAST(o.order_date AS DATE)                      AS order_date_key,
        o.order_status,

        -- Surrogate keys (for BI joins)
        c.customer_key,
        p.product_key,
        cat.category_key,
        d.department_key,

        -- Natural keys (for debugging / lineage)
        o.order_customer_id                             AS customer_id,
        oi.order_item_product_id                        AS product_id,
        p.category_id,
        cat.department_id,

        -- Customer attributes (point-in-time)
        c.customer_fname,
        c.customer_lname,
        c.customer_city,
        c.customer_state,
        c.customer_zipcode,

        -- Product attributes (point-in-time)
        p.product_name,
        p.product_price                                 AS current_product_price,

        -- Category attributes (point-in-time)
        cat.category_name,

        -- Department attributes (point-in-time)
        d.department_name,

        -- Measures
        oi.order_item_quantity                          AS quantity,
        oi.order_item_product_price                     AS unit_price,
        oi.order_item_quantity * oi.order_item_product_price AS gross_sales_amount,
        oi.order_item_subtotal                          AS net_sales_amount,
        (oi.order_item_quantity * oi.order_item_product_price)
            - oi.order_item_subtotal                    AS discount_amount,

        -- Audit
        CURRENT_TIMESTAMP()                             AS dbt_loaded_at

    FROM order_items oi

    INNER JOIN orders o
        ON oi.order_item_order_id = o.order_id

    -- SCD2 join: customer version active at order_date
    LEFT JOIN {{ ref('dim_customers') }} c
        ON o.order_customer_id = c.customer_id
        AND o.order_date >= c.dbt_valid_from
        AND o.order_date < COALESCE(c.dbt_valid_to, '9999-12-31'::TIMESTAMP)

    -- SCD2 join: product version active at order_date
    LEFT JOIN {{ ref('dim_products') }} p
        ON oi.order_item_product_id = p.product_id
        AND o.order_date >= p.dbt_valid_from
        AND o.order_date < COALESCE(p.dbt_valid_to, '9999-12-31'::TIMESTAMP)

    -- SCD2 join: category version active at order_date (via product's category_id)
    LEFT JOIN {{ ref('dim_categories') }} cat
        ON p.category_id = cat.category_id
        AND o.order_date >= cat.dbt_valid_from
        AND o.order_date < COALESCE(cat.dbt_valid_to, '9999-12-31'::TIMESTAMP)

    -- SCD2 join: department version active at order_date (via category's department_id)
    LEFT JOIN {{ ref('dim_departments') }} d
        ON cat.department_id = d.department_id
        AND o.order_date >= d.dbt_valid_from
        AND o.order_date < COALESCE(d.dbt_valid_to, '9999-12-31'::TIMESTAMP)
)

SELECT * FROM final

{% if is_incremental() %}
WHERE order_date > (
    SELECT COALESCE(MAX(order_date), '1900-01-01')
    FROM {{ this }}
)
{% endif %}
