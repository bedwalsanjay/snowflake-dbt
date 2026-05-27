import aws_cdk as cdk
from aws_cdk import (
    aws_ecs as ecs,
    aws_ec2 as ec2,
    aws_iam as iam,
    aws_ecr as ecr,
    aws_logs as logs,
)
from constructs import Construct


class EcsStack(cdk.Stack):
    def __init__(self, scope: Construct, construct_id: str, ecr_repo: ecr.Repository, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # ── VPC (use default to avoid NAT gateway costs) ──────────────
        vpc = ec2.Vpc.from_lookup(self, "DefaultVpc", is_default=True)

        # ── ECS Cluster ───────────────────────────────────────────────
        cluster = ecs.Cluster(self, "DbtCluster",
            cluster_name="dbt-snowflake-cluster",
            vpc=vpc
        )

        # ── Task Execution Role (ECS pulls image from ECR) ────────────
        execution_role = iam.Role(self, "EcsExecutionRole",
            role_name="dbt-ecs-execution-role",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonECSTaskExecutionRolePolicy"
                )
            ]
        )

        # ── Task Role (container permissions at runtime) ──────────────
        task_role = iam.Role(self, "EcsTaskRole",
            role_name="dbt-ecs-task-role",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonS3ReadOnlyAccess")
            ]
        )

        # ── CloudWatch Log Group ──────────────────────────────────────
        log_group = logs.LogGroup(self, "DbtLogGroup",
            log_group_name="/ecs/dbt-snowflake",
            removal_policy=cdk.RemovalPolicy.DESTROY,
            retention=logs.RetentionDays.ONE_WEEK
        )

        # ── Fargate Task Definition ───────────────────────────────────
        task_definition = ecs.FargateTaskDefinition(self, "DbtTaskDef",
            family="dbt-snowflake-task",
            cpu=512,        # 0.5 vCPU
            memory_limit_mib=1024,  # 1 GB
            execution_role=execution_role,
            task_role=task_role
        )

        # ── Container (image tag overridden at runtime by Airflow) ────
        task_definition.add_container("DbtContainer",
            container_name="dbt-snowflake",
            image=ecs.ContainerImage.from_ecr_repository(ecr_repo, tag="latest"),
            logging=ecs.LogDrivers.aws_logs(
                stream_prefix="dbt",
                log_group=log_group
            ),
            # Snowflake credentials injected as env vars at runtime by Airflow
            environment={
                "DBT_PROJECT_DIR": "/app/aws_snowflake_dbt"
            }
        )

        # ── Outputs ───────────────────────────────────────────────────
        cdk.CfnOutput(self, "ClusterName",
            value=cluster.cluster_name,
            description="ECS cluster name"
        )
        cdk.CfnOutput(self, "TaskDefinitionArn",
            value=task_definition.task_definition_arn,
            description="ECS task definition ARN"
        )
        cdk.CfnOutput(self, "TaskDefinitionFamily",
            value=task_definition.family,
            description="ECS task definition family name"
        )

        # expose for Airflow DAG reference
        self.cluster = cluster
        self.task_definition = task_definition
        self.vpc = vpc
