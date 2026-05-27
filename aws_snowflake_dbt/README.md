# aws_snowflake_dbt

dbt project for the Snowflake retail analytics pipeline.

## Models

### Staging — `ANALYTICS.STAGING`
Source-aligned models. One model per raw source table. Materialized as tables.

| Model | Source Table |
|---|---|
| stg_orders | GLUE_DATA.ORDERS.ORDERS |
| stg_order_items | GLUE_DATA.ORDERS.ORDER_ITEMS |
| stg_customers | GLUE_DATA.ORDERS.CUSTOMERS |
| stg_products | GLUE_DATA.ORDERS.PRODUCTS |
| stg_categories | GLUE_DATA.ORDERS.CATEGORIES |
| stg_departments | GLUE_DATA.ORDERS.DEPARTMENTS |

### Snapshots — `ANALYTICS.SNAPSHOTS`
SCD2 history tables using dbt's `check` strategy.

| Snapshot | Unique Key | Tracked Columns |
|---|---|---|
| snap_customers | customer_id | name, email, address |
| snap_products | product_id | category, name, description, price, image |
| snap_categories | category_id | department, name |
| snap_departments | department_id | name |

### Dimensions — `ANALYTICS.DIMENSIONS`
Built on top of snapshots. Each model generates a surrogate key from `(natural_key + dbt_valid_from)`. The first version of every record is backdated to `1900-01-01` so historical orders resolve correctly on date-range joins.

| Model | Surrogate Key |
|---|---|
| dim_customers | customer_key |
| dim_products | product_key |
| dim_categories | category_key |
| dim_departments | department_key |

### Facts — `ANALYTICS.MARTS`
Incremental fact table at order item grain.

| Model | Grain | Unique Key |
|---|---|---|
| fact_sales | one row per order item | order_item_id |

Joins all four dimensions using SCD2 date-range logic to ensure historical accuracy.

## Packages

- `dbt-labs/dbt_utils==1.3.0` — used for `generate_surrogate_key()`

Run `dbt deps` to install.

## Run Order

```bash
dbt run --select staging
dbt snapshot
dbt run --select marts.dimensions
dbt run --select marts.facts
dbt test
```

## Custom Macro

`macros/generate_schema_name.sql` — returns the configured custom schema name directly, preventing dbt from prefixing it with the target schema.
