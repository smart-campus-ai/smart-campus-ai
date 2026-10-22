# Partial S3 backend configuration for the dev environment (ADR-0011).
# Replace the two placeholders with the infra/bootstrap outputs, then:
#   tofu -chdir=infra/stacks/<stack> init -backend-config=../../envs/dev/backend.hcl -backend-config="key=dev/<stack>.tfstate"
# The state key is passed per stack (foundation, platform) so that one file serves both stacks:
#   dev/foundation.tfstate, dev/platform.tfstate
bucket       = "<from bootstrap output: state_bucket_name>"
region       = "eu-west-3"
use_lockfile = true # native S3 locking, no DynamoDB table
encrypt      = true
kms_key_id   = "<from bootstrap output: state_kms_key_arn>" # full ARN, required by the bucket policy
