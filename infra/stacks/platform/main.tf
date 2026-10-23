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
#
# The ARNs come from parameters that anyone able to write SSM could change: each one must be a key of this account, in
# this region and partition, otherwise a policy or a log group would point at a foreign key. The postcondition fails the
# plan (and so the apply) before any consumer of the value is evaluated.
data "aws_ssm_parameter" "kms" {
  for_each = toset(["data", "logs", "ai"])

  name            = "${local.foundation_ssm_prefix}/kms/${each.key}/arn"
  with_decryption = false

  lifecycle {
    postcondition {
      condition     = can(regex("^arn:${data.aws_partition.current.partition}:kms:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:key/[0-9a-f-]+$", self.insecure_value))
      error_message = "The foundation KMS parameter of the ${each.key} domain is not a key ARN of this account, region and partition (expected arn:${data.aws_partition.current.partition}:kms:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:key/<key-id>). Check the SSM parameter ${local.foundation_ssm_prefix}/kms/${each.key}/arn for tampering."
    }
  }
}
