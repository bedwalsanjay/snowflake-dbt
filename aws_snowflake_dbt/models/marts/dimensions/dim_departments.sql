WITH source AS (
    SELECT
        department_id,
        department_name,
        dbt_valid_to,
        dbt_scd_id,
        dbt_updated_at,
        CASE
            WHEN ROW_NUMBER() OVER (PARTITION BY department_id ORDER BY dbt_valid_from) = 1
                THEN '1900-01-01'::TIMESTAMP
            ELSE dbt_valid_from
        END AS dbt_valid_from
    FROM {{ ref('snap_departments') }}
)

SELECT
    {{ dbt_utils.generate_surrogate_key(['department_id', 'dbt_valid_from']) }} AS department_key,
    department_id,
    department_name,
    dbt_valid_from,
    dbt_valid_to,
    dbt_scd_id,
    dbt_updated_at
FROM source
