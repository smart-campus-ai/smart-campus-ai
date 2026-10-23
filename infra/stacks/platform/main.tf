# Platform stack: edge, identity, api, data, compute, ai and notifications of one environment. The composition is split
# by family (identity.tf, edge.tf, api.tf, data.tf, scheduler.tf, notifications.tf, ai.tf, compute.tf, iam.tf, ssm.tf).
#
# Cross-stack contract (no terraform_remote_state): the KMS keys come from the foundation stack through SSM, the
# values the application pipeline needs are published back under /smartcampus/<env>/platform/ (ssm.tf).

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

# KMS key ARNs published by the foundation stack (EN-14) as plain String parameters, one per domain:
#   /smartcampus/<env>/foundation/kms/data/arn
#   /smartcampus/<env>/foundation/kms/logs/arn
#   /smartcampus/<env>/foundation/kms/ai/arn
# A key ARN is not a secret: insecure_value avoids the sensitive marking (the ARNs are used in validations and policies),
# and with_decryption = false means the read-only plan role is never asked for kms:Decrypt.
data "aws_ssm_parameter" "kms" {
  for_each = toset(["data", "logs", "ai"])

  name            = "${local.foundation_ssm_prefix}/kms/${each.key}/arn"
  with_decryption = false
}
