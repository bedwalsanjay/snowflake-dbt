SELECT
    category_id,
    category_department_id,
    category_name
FROM {{ source('orders_src', 'CATEGORIES') }}
