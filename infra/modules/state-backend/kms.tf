# Key policy: explicit principals only, never "*".
#
# - EnableIamDelegation: the account root principal. This is what really delegates to IAM: a principal in the account
#   can use the key only if its own IAM policy allows it (the EN-13 CI roles get usage through IAM, not through this
#   policy). Usage actions only.
# - RootLockoutRecovery: the minimum the account root keeps to recover from a lockout (AWS guidance). It deliberately
#   excludes ScheduleKeyDeletion and DisableKey, which stay reserved to the key administrators.
# - KeyAdministration: the named bootstrap human / break-glass principals. The only way to administer the key.
#
# Resources are "*" because, in a key policy, "*" means "this key" (no resource-level scoping exists there).
data "aws_iam_policy_document" "key" {
  # checkov:skip=CKV_AWS_111: Key policy: Resource "*" means this key only; write access is limited to named admin principals.
  # checkov:skip=CKV_AWS_356: Key policy: Resource "*" is the only valid value and refers to the key itself.
  # checkov:skip=CKV_AWS_109: Key policy: PutKeyPolicy is limited to the admin principals and the account root (AWS lockout guidance).
  statement {
    sid       = "EnableIamDelegation"
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey",
      "kms:GenerateDataKeyWithoutPlaintext",
      "kms:ReEncryptFrom",
      "kms:ReEncryptTo",
    ]

    principals {
      type        = "AWS"
      identifiers = [local.account_root_arn]
    }
  }

  statement {
    sid       = "RootLockoutRecovery"
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "kms:DescribeKey",
      "kms:GetKeyPolicy",
      "kms:PutKeyPolicy",
    ]

    principals {
      type        = "AWS"
      identifiers = [local.account_root_arn]
    }
  }

  statement {
    sid       = "KeyAdministration"
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "kms:CancelKeyDeletion",
      "kms:CreateAlias",
      "kms:DeleteAlias",
      "kms:DescribeKey",
      "kms:DisableKey",
      "kms:DisableKeyRotation",
      "kms:EnableKey",
      "kms:EnableKeyRotation",
      "kms:GetKeyPolicy",
      "kms:GetKeyRotationStatus",
      "kms:ListResourceTags",
      "kms:PutKeyPolicy",
      "kms:ScheduleKeyDeletion",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:UpdateAlias",
    ]

    principals {
      type        = "AWS"
      identifiers = var.admin_principal_arns
    }
  }
}

resource "aws_kms_key" "this" {
  description              = "Encrypts the OpenTofu state bucket and the client-side state and plan encryption (${var.name_prefix})"
  deletion_window_in_days  = var.kms_deletion_window_in_days
  enable_key_rotation      = true
  rotation_period_in_days  = 365
  is_enabled               = true
  key_usage                = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  policy                   = data.aws_iam_policy_document.key.json

  tags = merge(var.tags, { Name = "${var.name_prefix}-tfstate" })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "this" {
  name          = local.kms_alias
  target_key_id = aws_kms_key.this.key_id
}
