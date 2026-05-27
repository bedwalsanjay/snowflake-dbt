#!/bin/bash
set -e

# Write profiles.yml from environment variables injected by ECS/Airflow
mkdir -p ~/.dbt
cat > ~/.dbt/profiles.yml << EOF
aws_snowflake_dbt:
  target: dev
  outputs:
    dev:
      type: snowflake
      account: ${SNOWFLAKE_ACCOUNT}
      user: ${SNOWFLAKE_USER}
      password: ${SNOWFLAKE_PASSWORD}
      role: ${SNOWFLAKE_ROLE}
      warehouse: ${SNOWFLAKE_WAREHOUSE}
      database: ANALYTICS
      schema: STAGING
      threads: 4
      client_session_keep_alive: false
EOF

# Execute the dbt command passed as argument from Airflow ECSOperator
exec uv run dbt "$@"
