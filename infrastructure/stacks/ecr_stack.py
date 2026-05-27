import aws_cdk as cdk
from aws_cdk import aws_ecr as ecr
from constructs import Construct


class EcrStack(cdk.Stack):
    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        self.repo = ecr.Repository(
            self, "DbtSnowflakeRepo",
            repository_name="dbt-snowflake",
            removal_policy=cdk.RemovalPolicy.DESTROY,
            # keep last 3 images, auto-delete older ones
            lifecycle_rules=[
                ecr.LifecycleRule(
                    max_image_count=3,
                    description="Keep last 3 images"
                )
            ]
        )

        cdk.CfnOutput(self, "EcrRepoUri",
            value=self.repo.repository_uri,
            description="ECR repository URI"
        )
