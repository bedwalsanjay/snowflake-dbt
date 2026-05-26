{% snapshot snap_categories %}

{{
    config(
      target_database='ANALYTICS',
      target_schema='SNAPSHOTS',
      unique_key='category_id',
      strategy='check',
      check_cols=[
        'category_department_id',
        'category_name'
      ]
    )
}}

SELECT
    category_id,
    category_department_id,
    category_name
FROM {{ ref('stg_categories') }}

{% endsnapshot %}
