WITH source AS (
    SELECT
        product_id,
        product_category_id AS category_id,
        product_name,
        product_description,
        product_price,
        product_image,
        dbt_valid_to,
        dbt_scd_id,
        dbt_updated_at,
        CASE
            WHEN ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY dbt_valid_from) = 1
                THEN '1900-01-01'::TIMESTAMP
            ELSE dbt_valid_from
        END AS dbt_valid_from
    FROM {{ ref('snap_products') }}
)

SELECT
    {{ dbt_utils.generate_surrogate_key(['product_id', 'dbt_valid_from']) }} AS product_key,
    product_id,
    category_id,
    product_name,
    product_description,
    product_price,
    product_image,
    dbt_valid_from,
    dbt_valid_to,
    dbt_scd_id,
    dbt_updated_at
FROM source
