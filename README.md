# Snowflake dbt Retail Pipeline

This repository contains a small Snowflake + dbt project that loads retail order data, models it into staging and mart tables, and demonstrates dbt snapshots for slowly changing dimensions.

The project is organized around a sample retail dataset with orders, order items, customers, products, categories, and departments.

## Project Layout

```text
.
|-- aws_snowflake_dbt/        # Main dbt project
|   |-- dbt_project.yml       # dbt project configuration
|   |-- macros/               # Custom dbt macros
|   |-- models/
|   |   |-- staging/          # Source-aligned staging models
|   |   |-- marts/            # Analytics-ready mart models
|   |   `-- demo/             # Simple demo model
|   `-- snapshots/            # dbt snapshot definitions
|-- sample_data/              # Local retail sample data in CSV and JSON formats
|-- src/sqls/                 # Snowflake setup, load, and validation SQL
|-- main.py                   # Minimal Python entrypoint
|-- pyproject.toml            # Python project metadata and dbt dependencies
`-- uv.lock                   # uv dependency lock file
```

## What This Project Builds

### Snowflake Source Layer

The raw source tables are expected in:

```text
GLUE_DATA.ORDERS
```

dbt sources are defined in `aws_snowflake_dbt/models/staging/src_orders.yml` for:

- `ORDERS`
- `ORDER_ITEMS`
- `CUSTOMERS`
- `PRODUCTS`
- `CATEGORIES`
- `DEPARTMENTS`

Setup and load scripts are stored under `src/sqls/`:

- `ddls.sql` creates Snowflake databases and source tables.
- `stage_fileFormats.sql` creates a CSV file format and external S3 stage.
- `DMLs.sql` loads CSV files from the stage into Snowflake tables.
- `table_counts.sql` validates loaded row counts.

### dbt Staging Layer

The staging models read from the raw Snowflake source tables and materialize as tables in:

```text
ANALYTICS.STAGING
```

Configured staging models:

- `stg_orders`
- `stg_order_items`
- `stg_customers`
- `stg_products`
- `stg_categories`
- `stg_departments`

Note: the current staging models include `limit 10`, so dbt runs only process a small sample from each source table.

### dbt Mart Layer

The mart model `fact_order_items` materializes incrementally in:

```text
ANALYTICS.MARTS
```

It joins staged order items with staged orders and calculates:

- order date keys
- customer and product references
- quantity and unit price
- gross sales amount
- net sales amount
- discount amount
- dbt load timestamp

### dbt Snapshots

Snapshot models are configured in:

```text
aws_snowflake_dbt/snapshots/
```

They write to:

```text
ANALYTICS.SNAPSHOTS
```

Configured snapshots:

- `snap_categories`
- `snap_customers`
- `snap_departments`
- `snap_products`

Each snapshot uses dbt's `check` strategy to track changes in selected columns.

## Prerequisites

- Python `3.12.0` or newer
- `uv`
- Snowflake account, warehouse, role, database, and schema access
- dbt Snowflake profile named `aws_snowflake_dbt`
- Access to the S3 stage location used in `src/sqls/stage_fileFormats.sql`

Python dependencies are declared in `pyproject.toml`:

- `dbt-core`
- `dbt-snowflake`

## Local Setup

Install dependencies:

```bash
uv sync
```

Activate the virtual environment if needed:

```bash
.venv\Scripts\activate
```

Run the simple Python entrypoint:

```bash
uv run python main.py
```

## Configure dbt

Create or update your dbt profile at:

```text
%USERPROFILE%\.dbt\profiles.yml
```

Example profile shape:

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

## Snowflake Setup Flow

Run the SQL scripts in this order from a Snowflake worksheet or SQL client:

1. Create databases and raw tables:

   ```sql
   -- src/sqls/ddls.sql
   ```

2. Create the file format and S3 stage:

   ```sql
   -- src/sqls/stage_fileFormats.sql
   ```

3. Load the CSV files:

   ```sql
   -- src/sqls/DMLs.sql
   ```

4. Validate row counts:

   ```sql
   -- src/sqls/table_counts.sql
   ```

Important notes:

- `DMLs.sql` contains empty AWS credential placeholders. Replace them with a secure Snowflake storage integration or temporary credentials before loading data.
- `DMLs.sql` loads `GLUE_DATA.ORDERS.ORDERS`, but the current `ddls.sql` file does not define the `ORDERS` table. Add that table definition before running the order load.

## Run dbt

From the dbt project directory:

```bash
cd aws_snowflake_dbt
dbt debug
dbt run
```

Run snapshots:

```bash
dbt snapshot
```

Run tests if tests are added:

```bash
dbt test
```

Clean generated dbt artifacts:

```bash
dbt clean
```

## dbt Configuration Summary

The dbt project is named `aws_snowflake_dbt` and uses the profile with the same name.

Model materializations are configured in `aws_snowflake_dbt/dbt_project.yml`:

- staging models: tables in `ANALYTICS.STAGING`
- mart models: tables in `ANALYTICS.MARTS`

The custom `generate_schema_name` macro returns the configured custom schema directly, instead of prefixing it with the target schema.

## Sample Data

Local sample files are available in:

```text
sample_data/retail_db/       # CSV files
sample_data/retail_db_json/  # JSON-style files
```

The Snowflake stage currently points to:

```text
s3://snowflake-orders-26may/source_data/
```

Upload the CSV files to that S3 path, or update the stage URL to match your own bucket.

## Development Notes

- Generated dbt artifacts such as `target/`, `dbt_packages/`, and logs are ignored by Git.
- `.venv/`, `.vscode/`, `logs/`, and `uv.lock` are listed in `.gitignore`.
- The nested `aws_snowflake_dbt/README.md` is the default starter dbt README; this root README describes the actual repository workflow.
