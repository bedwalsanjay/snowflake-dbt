WITH source AS (
    SELECT
        customer_id,
        customer_fname,
        customer_lname,
        customer_email,
        customer_street,
        customer_city,
        customer_state,
        customer_zipcode,
        dbt_valid_to,
        dbt_scd_id,
        dbt_updated_at,
        -- First version per customer gets backdated to epoch so historical
        -- orders (pre-snapshot) resolve correctly on date-range joins.
        -- Subsequent real SCD2 versions keep their actual valid_from.
        CASE
            WHEN ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY dbt_valid_from) = 1
                THEN '1900-01-01'::TIMESTAMP
            ELSE dbt_valid_from
        END AS dbt_valid_from
    FROM {{ ref('snap_customers') }}
)

SELECT
    {{ dbt_utils.generate_surrogate_key(['customer_id', 'dbt_valid_from']) }} AS customer_key,
    customer_id,
    customer_fname,
    customer_lname,
    customer_email,
    customer_street,
    customer_city,
    customer_state,
    customer_zipcode,
    dbt_valid_from,
    dbt_valid_to,
    dbt_scd_id,
    dbt_updated_at
FROM source
