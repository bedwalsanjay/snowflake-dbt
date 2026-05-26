{{ config(
    materialized='incremental',
    unique_key='order_item_id'
) }}

WITH order_items AS (
    SELECT *
    FROM {{ ref('stg_order_items') }}
),

orders AS (
    SELECT *
    FROM {{ ref('stg_orders') }}
),

final AS (
    SELECT
        oi.order_item_id,

        oi.order_item_order_id AS order_id,
        o.order_date,
        CAST(o.order_date AS DATE) AS order_date_key,

        o.order_customer_id AS customer_id,
        oi.order_item_product_id AS product_id,

        o.order_status,

        oi.order_item_quantity AS quantity,
        oi.order_item_product_price AS unit_price,

        oi.order_item_quantity * oi.order_item_product_price AS gross_sales_amount,
        oi.order_item_subtotal AS net_sales_amount,

        oi.order_item_quantity * oi.order_item_product_price
            - oi.order_item_subtotal AS discount_amount,

        CURRENT_TIMESTAMP() AS dbt_loaded_at

    FROM order_items oi
    INNER JOIN orders o
        ON oi.order_item_order_id = o.order_id
)

SELECT *
FROM final

{% if is_incremental() %}

WHERE order_date > (
    SELECT COALESCE(MAX(order_date), '1900-01-01')
    FROM {{ this }}
)

{% endif %}
