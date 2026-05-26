{% snapshot snap_customers %}

{{
    config(
      target_database='ANALYTICS',
      target_schema='SNAPSHOTS',
      unique_key='customer_id',
      strategy='check',
      check_cols=[
        'customer_fname',
        'customer_lname',
        'customer_email',
        'customer_street',
        'customer_city',
        'customer_state',
        'customer_zipcode'
      ]
    )
}}

SELECT
    customer_id,
    customer_fname,
    customer_lname,
    customer_email,
    customer_street,
    customer_city,
    customer_state,
    customer_zipcode
FROM {{ ref('stg_customers') }}

{% endsnapshot %}
