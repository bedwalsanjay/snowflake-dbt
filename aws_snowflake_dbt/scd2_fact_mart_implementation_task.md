# Detailed Implementation Task: Build SCD2-Aware Sales Fact Mart in dbt + Snowflake

# Objective

Create a production-grade `fact_sales` mart in dbt and Snowflake using proper dimensional modeling principles.

The fact table grain should be:

```text
One row per order item
```

The fact table must contain:

- Transaction identifiers
- Foreign keys to all related dimensions
- Historical SCD2-aware dimension mappings
- Sales measures
- Audit columns

Because all dimensions are implemented as SCD2 snapshots, the fact table must join dimensions using:

```text
Natural Key + Effective Date Range
```

Meaning:

```sql
order_date >= dbt_valid_from
AND order_date < dbt_valid_to
```

This ensures the fact row points to the correct historical version of each dimension.

---

# Final Target Architecture

```text
Raw Tables
    ↓
Staging Models
    ↓
Snapshots (SCD2)
    ↓
Dimension Models
    ↓
Fact Sales Mart
    ↓
BI / Analytics
```

---

# Step 1: Validate Required Staging Models

The following staging models must exist.

## Required Models

```text
stg_orders
stg_order_items
stg_customers
stg_products
stg_categories
stg_departments
```

---

# Step 2: Validate Business Relationships

The following business relationships should exist.

## Orders to Customers

```text
orders.customer_id → customers.customer_id
```

## Order Items to Orders

```text
order_items.order_id → orders.order_id
```

## Order Items to Products

```text
order_items.product_id → products.product_id
```

## Products to Categories

```text
products.category_id → categories.category_id
```

## Categories to Departments

```text
categories.department_id → departments.department_id
```

---

# Step 3: Create SCD2 Snapshots

Create snapshots for all slowly changing dimensions.

## Required Snapshots

```text
snap_customers
snap_products
snap_categories
snap_departments
```

---

# Step 4: Snapshot Design Requirements

Each snapshot should contain:

```text
Business/Natural Key
Business Attributes
dbt_valid_from
dbt_valid_to
dbt_scd_id
dbt_updated_at
```

---

# Step 5: Example Customer Snapshot

File:

```text
snapshots/snap_customers.sql
```

Example:

```sql
{% snapshot snap_customers %}

{{
    config(
        target_schema='snapshots',
        unique_key='customer_id',
        strategy='timestamp',
        updated_at='updated_at'
    )
}}

SELECT
    customer_id,
    customer_fname,
    customer_lname,
    customer_email,
    customer_city,
    customer_state,
    updated_at

FROM {{ ref('stg_customers') }}

{% endsnapshot %}
```

---

# Step 6: Create Similar Snapshots

Create similar snapshots for:

- Products
- Categories
- Departments

Each snapshot should track historical changes independently.

---

# Step 7: Create Dimension Models on Top of Snapshots

Do not directly join facts with raw snapshots.

Instead, create clean business dimension models.

## Required Dimension Models

```text
dim_customers
dim_products
dim_categories
dim_departments
```

---

# Step 8: Why Create Dimensions on Top of Snapshots

## Reason

Snapshots are technical history tables.

Dimension models are business-friendly reusable semantic models.

This separation improves:

- Maintainability
- Reusability
- Readability
- Governance
- Testing
- BI consumption

---

# Step 9: Generate Surrogate Keys in Dimensions

Each SCD2 version must have a unique surrogate key.

## Important Rule

Every historical version must generate a different key.

---

# Step 10: Customer Dimension Example

File:

```text
models/marts/dim_customers.sql
```

Example:

```sql
SELECT

    {{ dbt_utils.generate_surrogate_key([
        'customer_id',
        'dbt_valid_from'
    ]) }} AS customer_key,

    customer_id,
    customer_fname,
    customer_lname,
    customer_email,
    customer_city,
    customer_state,

    dbt_valid_from,
    dbt_valid_to,
    dbt_scd_id,
    dbt_updated_at

FROM {{ ref('snap_customers') }}
```

---

# Step 11: Generate Surrogate Keys for All Dimensions

## Product Dimension

```sql
{{ dbt_utils.generate_surrogate_key([
    'product_id',
    'dbt_valid_from'
]) }} AS product_key
```

## Category Dimension

```sql
{{ dbt_utils.generate_surrogate_key([
    'category_id',
    'dbt_valid_from'
]) }} AS category_key
```

## Department Dimension

```sql
{{ dbt_utils.generate_surrogate_key([
    'department_id',
    'dbt_valid_from'
]) }} AS department_key
```

---

# Step 12: Create Final Fact Mart

Create final model:

```text
fact_sales.sql
```

Materialization:

```sql
materialized='incremental'
```

Unique key:

```sql
unique_key='order_item_id'
```

---

# Step 13: Fact Table Grain

## Grain Definition

```text
One row per order item
```

This means:

- Each order item becomes one fact row
- No aggregation inside fact
- Lowest transaction granularity

---

# Step 14: Fact Table Required Columns

## Transaction Columns

```text
order_item_id
order_id
order_date
order_date_key
```

## Dimension Foreign Keys

```text
customer_key
product_key
category_key
department_key
```

## Optional Natural Keys

Useful for debugging and lineage.

```text
customer_id
product_id
category_id
department_id
```

## Measures

```text
quantity
unit_price
gross_sales_amount
discount_amount
net_sales_amount
```

## Audit Columns

```text
dbt_loaded_at
```

---

# Step 15: Fact Table Join Logic

The fact table must join dimensions using:

```text
Natural Key + Date Range
```

---

# Step 16: Customer SCD2 Join Example

```sql
LEFT JOIN {{ ref('dim_customers') }} c
    ON o.order_customer_id = c.customer_id
   AND o.order_date >= c.dbt_valid_from
   AND o.order_date < COALESCE(
        c.dbt_valid_to,
        '9999-12-31'
   )
```

---

# Step 17: Product SCD2 Join Example

```sql
LEFT JOIN {{ ref('dim_products') }} p
    ON oi.order_item_product_id = p.product_id
   AND o.order_date >= p.dbt_valid_from
   AND o.order_date < COALESCE(
        p.dbt_valid_to,
        '9999-12-31'
   )
```

---

# Step 18: Category SCD2 Join Example

```sql
LEFT JOIN {{ ref('dim_categories') }} cat
    ON p.category_id = cat.category_id
   AND o.order_date >= cat.dbt_valid_from
   AND o.order_date < COALESCE(
        cat.dbt_valid_to,
        '9999-12-31'
   )
```

---

# Step 19: Department SCD2 Join Example

```sql
LEFT JOIN {{ ref('dim_departments') }} d
    ON cat.department_id = d.department_id
   AND o.order_date >= d.dbt_valid_from
   AND o.order_date < COALESCE(
        d.dbt_valid_to,
        '9999-12-31'
   )
```

---

# Step 20: Why Date Range Join is Critical

Example:

```text
Product originally belonged to Category A
Later product moved to Category B
```

If an order happened before the category change:

```text
Fact must still point to Category A version
```

Without SCD2 date joins:

- Historical analytics become incorrect
- Revenue history changes incorrectly
- BI reports become unreliable

---

# Step 21: Measures Calculation Logic

## Quantity

```sql
oi.order_item_quantity AS quantity
```

## Unit Price

```sql
oi.order_item_product_price AS unit_price
```

## Gross Sales

```sql
oi.order_item_quantity
*
oi.order_item_product_price
```

## Net Sales

```sql
oi.order_item_subtotal
```

## Discount Amount

```sql
(
    oi.order_item_quantity
    *
    oi.order_item_product_price
)
-
oi.order_item_subtotal
```

---

# Step 22: Incremental Load Logic

Fact table should use incremental loading.

Example:

```sql
{% if is_incremental() %}

WHERE order_date > (
    SELECT COALESCE(MAX(order_date), '1900-01-01')
    FROM {{ this }}
)

{% endif %}
```

---

# Step 23: Important Incremental Consideration

If late-arriving records are possible, consider:

```sql
WHERE order_date >= DATEADD(day, -7, (
    SELECT MAX(order_date)
    FROM {{ this }}
))
```

This creates a rolling reprocessing window.

---

# Step 24: Add dbt Tests

## Required Tests

### Unique Test

```yaml
unique:
  - order_item_id
```

### Not Null Tests

```yaml
not_null:
  - customer_key
  - product_key
  - category_key
  - department_key
```

### Relationship Tests

```yaml
relationships:
```

Validate foreign keys against dimensions.

---

# Step 25: Validate Final Star Schema

Final architecture should look like:

```text
                dim_customers
                       |
                       |
dim_departments ← dim_categories ← dim_products
                       |
                       |
                  fact_sales
                       |
                       |
                  dim_dates
```

---

# Step 26: Expected Analytics Capability

After implementation, business users can correctly analyze:

- Sales by customer
- Sales by city
- Sales by state
- Sales by product
- Sales by category
- Sales by department
- Historical product category movement
- Historical customer segmentation
- Revenue trends over time

All with historical accuracy.

---

# Step 27: dbt Execution Flow

Recommended execution order:

```text
dbt run staging
    ↓
dbt snapshot
    ↓
dbt run dimensions
    ↓
dbt run fact marts
```

---

# Step 28: Recommended Folder Structure

```text
models/
│
├── staging/
│
├── snapshots/
│
├── marts/
│   ├── dimensions/
│   │   ├── dim_customers.sql
│   │   ├── dim_products.sql
│   │   ├── dim_categories.sql
│   │   └── dim_departments.sql
│   │
│   └── facts/
│       └── fact_sales.sql
```

---

# Step 29: Final Deliverables

## Deliverables Checklist

### Snapshots

- snap_customers
- snap_products
- snap_categories
- snap_departments

### Dimensions

- dim_customers
- dim_products
- dim_categories
- dim_departments

### Fact

- fact_sales

### Tests

- uniqueness tests
- not null tests
- relationship tests

### Documentation

- model descriptions
- column descriptions
- lineage validation

---

# Step 30: Final Expected Outcome

At the end of implementation:

- Full star schema will exist
- Historical tracking will work correctly
- Fact table will contain proper foreign keys
- Analytics will become historically accurate
- dbt lineage will become enterprise-grade
- Snowflake warehouse design will resemble real production architecture
