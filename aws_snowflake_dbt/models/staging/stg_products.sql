SELECT
    product_id,
    product_category_id,
    product_name,
    product_description,
    product_price,
    product_image
FROM {{ source('orders_src', 'PRODUCTS') }}