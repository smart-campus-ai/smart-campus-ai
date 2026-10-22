# Partial S3 backend configuration for the prod environment (ADR-0011).
# Same bucket and KMS key as dev during the workshop (single account, ADR-0002); only the state key differs.
# Replace the two placeholders with the infra/bootstrap outputs, then:
#   tofu -chdir=infra/stacks/<stack> init -backend-config=../../envs/prod/backend.hcl -backend-config="key=prod/<stack>.tfstate"
# State keys: prod/foundation.tfstate, prod/platform.tfstate
bucket       = "<from bootstrap output: state_bucket_name>"
region       = "eu-west-3"
use_lockfile = true # native S3 locking, no DynamoDB table
encrypt      = true
kms_key_id   = "<from bootstrap output: state_kms_key_arn>" # full ARN, required by the bucket policy
