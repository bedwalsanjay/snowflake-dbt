FROM python:3.12-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install uv
RUN pip install uv==0.7.8

# Copy dependency files first (layer caching)
COPY pyproject.toml uv.lock ./

# Install Python dependencies
RUN uv sync --frozen --no-dev

# Copy dbt project
COPY aws_snowflake_dbt/ ./aws_snowflake_dbt/

# Install dbt packages
RUN cd aws_snowflake_dbt && uv run dbt deps

# profiles.yml is injected at runtime via environment variables
# using the entrypoint script below
COPY entrypoint.sh ./
RUN chmod +x entrypoint.sh

WORKDIR /app/aws_snowflake_dbt

ENTRYPOINT ["/app/entrypoint.sh"]
