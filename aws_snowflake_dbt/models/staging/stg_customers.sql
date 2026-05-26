SELECT
    customer_id,
    customer_fname,
    customer_lname,
    customer_email,
    customer_password,
    customer_street,
    customer_city,
    customer_state,
    customer_zipcode
FROM {{ source('orders_src', 'CUSTOMERS') }}  limit 10
