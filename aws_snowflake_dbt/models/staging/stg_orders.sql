SELECT
    order_id,
    TO_TIMESTAMP(order_date) AS order_date,
    order_customer_id,
    order_status
FROM {{ source('orders_src', 'ORDERS') }} limit 10
