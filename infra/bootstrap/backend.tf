# Backend of the bootstrap itself (ADR-0011).
#
# Step 1 - first apply: state stays LOCAL (terraform.tfstate, git-ignored) because the bucket does not exist yet.
#          The state holds no secret (ARNs and names only). Run by a human, plan reviewed before apply.
#
# Step 2 - migrate: uncomment the block below, replace the placeholders with the apply outputs, then run
#          tofu -chdir=infra/bootstrap init -migrate-state
#          and delete the local state files after checking the object exists in the bucket.
#
# terraform {
#   backend "s3" {
#     bucket       = "<state_bucket_name output>"
#     key          = "bootstrap/bootstrap.tfstate"
#     region       = "us-east-1"
#     use_lockfile = true
#     encrypt      = true
#     kms_key_id   = "<state_kms_key_arn output>" # full ARN: the bucket policy refuses other key references
#   }
# }
#
# Optional step 3 - client-side encryption of the bootstrap state, same pattern as the stacks:
# add an `encryption` block (key_provider "aws_kms" on state_kms_key_arn, method "aes_gcm") with a
# `fallback { method = method.unencrypted.migrate }` for the migration run, then remove the fallback
# and set `enforced = true`.
