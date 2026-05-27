# Snowflake dbt Retail Pipeline

A production-grade retail analytics pipeline built on AWS S3 + Snowflake + dbt. It ingests raw retail order data, models it through staging, SCD2 snapshots, dimension, and fact layers, and produces a historically accurate star schema for BI consumption.

## Architecture

```text
┌─────────────────────────────────────────────────────────────────────────┐
│                          DATA SOURCES                                   │
│                                                                         │
│   orders.csv   order_items.csv   customers.csv   products.csv           │
│   categories.csv   departments.csv                                      │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │  upload manually / via script
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        AWS S3 BUCKET                                    │
│                                                                         │
│   s3://snowflake-orders-26may/source_data/                              │
│                                                                         │
│   part-00000_orders.csv          part-00000-order_items.csv             │
│   part-00000-customers.csv       part-00000-products.csv                │
│   part-00000-categories.csv      part-00000-departments.csv             │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │  Snowflake COPY INTO
                                │  via external stage @snowstage
                                │  (src/sqls/DMLs.sql)
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                   SNOWFLAKE — GLUE_DATA.ORDERS (Raw)                    │
│                                                                         │
│   ORDERS            ORDER_ITEMS         CUSTOMERS                       │
│   ├─ order_id       ├─ order_item_id    ├─ customer_id                  │
│   ├─ order_date     ├─ order_id         ├─ customer_fname               │
│   ├─ customer_id    ├─ product_id       ├─ customer_email               │
│   └─ order_status   ├─ quantity         └─ address fields               │
│                     ├─ subtotal                                         │
│   PRODUCTS          └─ product_price    CATEGORIES                      │
│   ├─ product_id                         ├─ category_id                  │
│   ├─ category_id    DEPARTMENTS         ├─ department_id                │
│   ├─ product_name   ├─ department_id    └─ category_name                │
│   └─ product_price  └─ department_name                                  │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │  dbt sources (staging.yml)
                                │  dbt run --select staging
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│               SNOWFLAKE — ANALYTICS.STAGING (dbt tables)                │
│                                                                         │
│   stg_orders        stg_order_items     stg_customers                   │
│   stg_products      stg_categories      stg_departments                 │
│                                                                         │
│   · Type casting (TO_TIMESTAMP on order_date)                           │
│   · dbt tests: unique, not_null on all PKs                              │
│   · accepted_values test on order_status                                │
└──────────────┬────────────────────────────────────────────────────────┘
               │                          │
               │  dbt snapshot            │  (staging models also feed
               ▼                          │   directly into fact_sales)
┌──────────────────────────────┐          │
│  ANALYTICS.SNAPSHOTS (SCD2)  │          │
│                              │          │
│  snap_customers              │          │
│  snap_products               │          │
│  snap_categories             │          │
│  snap_departments            │          │
│                              │          │
│  · strategy: check           │          │
│  · dbt_valid_from            │          │
│  · dbt_valid_to              │          │
│  · dbt_scd_id                │          │
│  · dbt_updated_at            │          │
└──────────────┬───────────────┘          │
               │  dbt run --select        │
               │  marts.dimensions        │
               ▼                          │
┌──────────────────────────────────────┐  │
│  ANALYTICS.DIMENSIONS (dbt tables)   │  │
│                                      │  │
│  dim_customers   dim_products        │  │
│  dim_categories  dim_departments     │  │
│                                      │  │
│  · surrogate key per SCD2 version    │  │
│    hash(natural_key + dbt_valid_from)│  │
│  · first version backdated to        │  │
│    1900-01-01 for historical joins   │  │
│  · dbt_valid_from / dbt_valid_to     │  │
│    preserved for date-range joins    │  │
└──────────────┬───────────────────────┘  │
               │                          │
               │  dbt run --select        │
               │  marts.facts             │
               │          ◄───────────────┘
               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│              ANALYTICS.MARTS.FACT_SALES (incremental table)             │
│                                                                         │
│  GRAIN: one row per order item                                          │
│                                                                         │
│  IDENTIFIERS          FOREIGN KEYS (surrogate)                          │
│  ├─ order_item_id     ├─ customer_key  → dim_customers                  │
│  ├─ order_id          ├─ product_key   → dim_products                   │
│  ├─ order_date        ├─ category_key  → dim_categories                 │
│  └─ order_date_key    └─ department_key→ dim_departments                │
│                                                                         │
│  SCD2 JOIN LOGIC                                                        │
│  order_date >= dim.dbt_valid_from                                       │
│  AND order_date < COALESCE(dim.dbt_valid_to, '9999-12-31')             │
│                                                                         │
│  DENORMALIZED ATTRIBUTES      MEASURES                                  │
│  ├─ customer_fname/lname      ├─ quantity                               │
│  ├─ customer_city/state       ├─ unit_price                             │
│  ├─ product_name              ├─ gross_sales_amount                     │
│  ├─ category_name             ├─ net_sales_amount                       │
│  └─ department_name           └─ discount_amount                        │
│                                                                         │
│  INCREMENTAL LOAD: WHERE order_date > MAX(order_date) in table          │
└─────────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        BI / ANALYTICS                                   │
│                                                                         │
│  · Sales by customer, city, state                                       │
│  · Sales by product                                                     │
│  · Sales by category                                                    │
│  · Sales by department                                                  │
│  · Historical dimension changes (SCD2 accuracy)                         │
│  · Revenue trends over time                                             │
└─────────────────────────────────────────────────────────────────────────┘
```

## Project Layout

```text
.
├── aws_snowflake_dbt/
│   ├── dbt_project.yml
│   ├── packages.yml                  # dbt-utils dependency
│   ├── macros/
│   │   └── generate_schema_name.sql  # custom schema macro
│   ├── models/
│   │   ├── staging/                  # source-aligned staging models
│   │   ├── marts/
│   │   │   ├── dimensions/           # SCD2 dimension models
│   │   │   │   ├── dim_customers.sql
│   │   │   │   ├── dim_products.sql
│   │   │   │   ├── dim_categories.sql
│   │   │   │   ├── dim_departments.sql
│   │   │   │   └── dimensions.yml
│   │   │   └── facts/
│   │   │       ├── fact_sales.sql
│   │   │       └── facts.yml
│   │   └── demo/
│   └── snapshots/
│       ├── snap_customers.sql
│       ├── snap_products.sql
│       ├── snap_categories.sql
│       ├── snap_departments.sql
│       └── snapshots.yml
├── sample_data/
│   ├── retail_db/                    # CSV files
│   └── retail_db_json/               # JSON-style files
├── src/sqls/                         # Snowflake setup SQL scripts
├── main.py
├── pyproject.toml
└── uv.lock
```

## What This Project Builds

### 1. Raw Source Layer — `GLUE_DATA.ORDERS`

Six tables loaded from S3 via Snowflake `COPY INTO`:

| Table | Description |
|---|---|
| ORDERS | Order header — id, date, customer, status |
| ORDER_ITEMS | Order lines — product, quantity, price, subtotal |
| CUSTOMERS | Customer master — name, email, address |
| PRODUCTS | Product master — name, category, price |
| CATEGORIES | Category master — name, department |
| DEPARTMENTS | Department master — name |

### 2. Staging Layer — `ANALYTICS.STAGING`

Six dbt models materialized as tables. Minimal transformation — column passthrough with type casting. Full dataset loaded (no row limits).

- `stg_orders`, `stg_order_items`, `stg_customers`, `stg_products`, `stg_categories`, `stg_departments`

dbt tests defined in `staging.yml`: `unique`, `not_null` on all PKs, `accepted_values` on `order_status`.

### 3. SCD2 Snapshots — `ANALYTICS.SNAPSHOTS`

Four snapshots using dbt's `check` strategy. Track historical changes to slowly changing dimensions.

| Snapshot | Tracks changes in |
|---|---|
| snap_customers | name, email, full address |
| snap_products | category, name, description, price, image |
| snap_categories | department, name |
| snap_departments | name |

dbt automatically adds `dbt_valid_from`, `dbt_valid_to`, `dbt_scd_id`, `dbt_updated_at` to each snapshot table.

### 4. Dimension Layer — `ANALYTICS.DIMENSIONS`

Four dimension models built on top of snapshots. Each generates a **surrogate key** by hashing `(natural_key + dbt_valid_from)` so every historical SCD2 version gets a unique key.

The first version of each record has `dbt_valid_from` backdated to `1900-01-01` so historical orders (pre-snapshot) resolve correctly on date-range joins.

| Model | Surrogate Key |
|---|---|
| dim_customers | customer_key |
| dim_products | product_key |
| dim_categories | category_key |
| dim_departments | department_key |

### 5. Fact Layer — `ANALYTICS.MARTS`

`fact_sales` — incremental table at **order item grain** (one row per order item).

Joins all four dimensions using SCD2 date-range logic:

```sql
LEFT JOIN dim_customers c
    ON o.order_customer_id = c.customer_id
   AND o.order_date >= c.dbt_valid_from
   AND o.order_date < COALESCE(c.dbt_valid_to, '9999-12-31')
```

This ensures each fact row points to the dimension version that was active **at the time of the order** — preserving historical accuracy even when dimension attributes change.

Key measures: `quantity`, `unit_price`, `gross_sales_amount`, `net_sales_amount`, `discount_amount`.

Denormalized attributes from all dimensions are included for direct BI querying without extra joins.

### 6. Custom Macro

`generate_schema_name` overrides dbt's default schema naming so models land in the exact configured schema (`STAGING`, `DIMENSIONS`, `MARTS`) rather than being prefixed with the target schema name.

---

## Prerequisites

- Python `3.12.0` or newer
- `uv`
- Snowflake account with warehouse, role, and database access
- dbt profile named `aws_snowflake_dbt` configured at `%USERPROFILE%\.dbt\profiles.yml`
- AWS S3 bucket accessible from Snowflake (via storage integration or credentials)

Python dependencies (`pyproject.toml`): `dbt-core`, `dbt-snowflake`

dbt package dependencies (`packages.yml`): `dbt-labs/dbt_utils==1.3.0`

---

## Local Setup

```bash
# Install Python dependencies
uv sync

# Activate virtual environment
.venv\Scripts\activate

# Install dbt packages
cd aws_snowflake_dbt
dbt deps
```

## Configure dbt Profile

Create `%USERPROFILE%\.dbt\profiles.yml`:

```yaml
aws_snowflake_dbt:
  target: dev
  outputs:
    dev:
      type: snowflake
      account: <your_account>
      user: <your_user>
      password: <your_password>
      role: <your_role>
      warehouse: <your_warehouse>
      database: ANALYTICS
      schema: STAGING
      threads: 4
      client_session_keep_alive: false
```

Do not commit real Snowflake credentials or AWS keys.

---

## Snowflake Setup

Run SQL scripts in order from a Snowflake worksheet:

```sql
-- 1. Create databases and raw tables
-- src/sqls/ddls.sql

-- 2. Create CSV file format and S3 external stage
-- src/sqls/stage_fileFormats.sql

-- 3. Load CSV files from S3
-- src/sqls/DMLs.sql   ← replace empty AWS credential placeholders first

-- 4. Validate row counts
-- src/sqls/table_counts.sql
```

---

## Run dbt Pipeline

From `aws_snowflake_dbt/`:

```bash
# Verify connection
dbt debug

# Full pipeline run (recommended order)
dbt run --select staging
dbt snapshot
dbt run --select marts.dimensions
dbt run --select marts.facts

# Run all tests
dbt test

# Generate and serve docs
dbt docs generate
dbt docs serve

# Clean artifacts
dbt clean
```

---

## Snowflake Schema Layout

| Schema | Contents |
|---|---|
| `GLUE_DATA.ORDERS` | Raw source tables |
| `ANALYTICS.STAGING` | dbt staging models |
| `ANALYTICS.SNAPSHOTS` | SCD2 snapshot tables |
| `ANALYTICS.DIMENSIONS` | Dimension models with surrogate keys |
| `ANALYTICS.MARTS` | Fact table (`fact_sales`) |

---

## Analytics Capabilities

After a full pipeline run, the star schema supports:

- Sales by customer, city, state
- Sales by product
- Sales by category
- Sales by department
- Historical product category movement
- Historical customer address changes
- Revenue trends over time

All with **historical accuracy** — fact rows always point to the dimension version active at order time.

---

## Sample Data

```text
sample_data/retail_db/       # CSV files (used for S3 upload)
sample_data/retail_db_json/  # JSON-style files (reference only)
```

S3 stage URL: `s3://snowflake-orders-26may/source_data/`

Upload CSV files to that path, or update `src/sqls/stage_fileFormats.sql` to point to your own bucket.

---

## Development Notes

- `target/`, `dbt_packages/`, and `logs/` are git-ignored.
- `.venv/`, `.vscode/`, and `uv.lock` are git-ignored.
- Do not commit `profiles.yml` or any file containing credentials.
