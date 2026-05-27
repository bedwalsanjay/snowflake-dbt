import os
import aws_cdk as cdk
from stacks.ecr_stack import EcrStack
from stacks.ecs_stack import EcsStack

app = cdk.App()

# env is required for VPC lookup (from_lookup needs account + region)
env = cdk.Environment(
    account=os.environ["CDK_DEFAULT_ACCOUNT"],
    region=os.environ["CDK_DEFAULT_REGION"]
)

ecr_stack = EcrStack(app, "EcrStack", env=env)

EcsStack(app, "EcsStack",
    ecr_repo=ecr_stack.repo,
    env=env
)

app.synth()
