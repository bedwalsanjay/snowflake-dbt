{% snapshot snap_products %}

{{
    config(
      target_database='ANALYTICS',
      target_schema='SNAPSHOTS',
      unique_key='product_id',
      strategy='check',
      check_cols=[
        'product_category_id',
        'product_name',
        'product_description',
        'product_price',
        'product_image'
      ]
    )
}}

SELECT
    product_id,
    product_category_id,
    product_name,
    product_description,
    product_price,
    product_image
FROM {{ ref('stg_products') }}

{% endsnapshot %}
