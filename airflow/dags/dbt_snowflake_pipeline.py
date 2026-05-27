from airflow import DAG
from airflow.providers.amazon.aws.operators.ecs import EcsRunTaskOperator
from airflow.models import Variable
from datetime import datetime

# ── Config from Airflow Variables ─────────────────────────────────────
AWS_REGION          = Variable.get("AWS_REGION")
ECS_CLUSTER         = Variable.get("ECS_CLUSTER")
ECS_TASK_DEFINITION = Variable.get("ECS_TASK_DEFINITION")
ECS_CONTAINER_NAME  = Variable.get("ECS_CONTAINER_NAME")
ECS_SUBNET_ID       = Variable.get("ECS_SUBNET_ID")
ECS_SECURITY_GROUP  = Variable.get("ECS_SECURITY_GROUP_ID")

# Snowflake credentials injected into each container at runtime
SNOWFLAKE_ENV = [
    {"name": "SNOWFLAKE_ACCOUNT",   "value": Variable.get("SNOWFLAKE_ACCOUNT")},
    {"name": "SNOWFLAKE_USER",      "value": Variable.get("SNOWFLAKE_USER")},
    {"name": "SNOWFLAKE_PASSWORD",  "value": Variable.get("SNOWFLAKE_PASSWORD")},
    {"name": "SNOWFLAKE_ROLE",      "value": Variable.get("SNOWFLAKE_ROLE")},
    {"name": "SNOWFLAKE_WAREHOUSE", "value": Variable.get("SNOWFLAKE_WAREHOUSE")},
]

# ── Shared ECS task config ─────────────────────────────────────────────
def ecs_task(task_id, dbt_command: list):
    """Returns an EcsRunTaskOperator for a given dbt command."""
    return EcsRunTaskOperator(
        task_id=task_id,
        cluster=ECS_CLUSTER,
        task_definition=ECS_TASK_DEFINITION,
        launch_type="FARGATE",
        aws_conn_id="aws_default",
        region=AWS_REGION,
        overrides={
            "containerOverrides": [
                {
                    "name": ECS_CONTAINER_NAME,
                    "command": dbt_command,
                    "environment": SNOWFLAKE_ENV,
                }
            ]
        },
        network_configuration={
            "awsvpcConfiguration": {
                "subnets": [ECS_SUBNET_ID],
                "securityGroups": [ECS_SECURITY_GROUP],
                "assignPublicIp": "ENABLED",   # needed for Fargate in public subnet
            }
        },
        awslogs_group="/ecs/dbt-snowflake",
        awslogs_region=AWS_REGION,
        awslogs_stream_prefix="dbt",
        awslogs_fetch_interval_seconds=10,
    )


# ── DAG ───────────────────────────────────────────────────────────────
with DAG(
    dag_id="dbt_snowflake_pipeline",
    start_date=datetime(2024, 1, 1),
    schedule=None,      # manual trigger only
    catchup=False,
    tags=["dbt", "snowflake", "ecs"],
) as dag:

    run_staging = ecs_task(
        task_id="run_staging",
        dbt_command=["run", "--select", "staging"]
    )

    run_snapshots = ecs_task(
        task_id="run_snapshots",
        dbt_command=["snapshot"]
    )

    run_dimensions = ecs_task(
        task_id="run_dimensions",
        dbt_command=["run", "--select", "marts.dimensions"]
    )

    run_facts = ecs_task(
        task_id="run_facts",
        dbt_command=["run", "--select", "marts.facts"]
    )

    run_tests = ecs_task(
        task_id="run_tests",
        dbt_command=["test"]
    )

    # ── Pipeline order ────────────────────────────────────────────────
    run_staging >> run_snapshots >> run_dimensions >> run_facts >> run_tests
