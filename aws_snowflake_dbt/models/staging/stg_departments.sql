SELECT
    department_id,
    department_name
FROM {{ source('orders_src', 'DEPARTMENTS') }}
