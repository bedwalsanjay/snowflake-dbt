WITH source AS (
    SELECT
        category_id,
        category_department_id AS department_id,
        category_name,
        dbt_valid_to,
        dbt_scd_id,
        dbt_updated_at,
        CASE
            WHEN ROW_NUMBER() OVER (PARTITION BY category_id ORDER BY dbt_valid_from) = 1
                THEN '1900-01-01'::TIMESTAMP
            ELSE dbt_valid_from
        END AS dbt_valid_from
    FROM {{ ref('snap_categories') }}
)

SELECT
    {{ dbt_utils.generate_surrogate_key(['category_id', 'dbt_valid_from']) }} AS category_key,
    category_id,
    department_id,
    category_name,
    dbt_valid_from,
    dbt_valid_to,
    dbt_scd_id,
    dbt_updated_at
FROM source
