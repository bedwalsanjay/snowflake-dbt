{% snapshot snap_departments %}

{{
    config(
      target_database='ANALYTICS',
      target_schema='SNAPSHOTS',
      unique_key='department_id',
      strategy='check',
      check_cols=[
        'department_name'
      ]
    )
}}

SELECT
    department_id,
    department_name
FROM {{ ref('stg_departments') }}

{% endsnapshot %}