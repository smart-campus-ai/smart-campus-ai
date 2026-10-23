env         = "dev"
name_prefix = "sc-dev"

# state_kms_key_arn (bootstrap output) is not stored here: pass TF_VAR_state_kms_key_arn or -var.
# admin_principal_arns is not stored here either (account ID and break-glass role names stay out of the repository):
#   TF_VAR_admin_principal_arns='["arn:aws:iam::<account-id>:role/<bootstrap-admin-role>","arn:aws:iam::<account-id>:role/<break-glass-role>"]'
# It must include the identity that runs the apply creating the keys, and never a CI role.

kms_deletion_window_in_days = 7

# Bedrock may use the ai key for the Knowledge Bases of the account, so the platform stack can create one at first apply.
enable_bedrock = true

# CloudFront needs no second apply: the edge key carries a grant scoped to the distributions of the account.
# The producer of the GuardDuty grant lives in the platform stack. Leave it empty at the first apply; once platform
# exists and enable_malware_protection is true, apply foundation again with the scan role ARN (platform output). The ARN
# carries the account ID, so pass it as TF_VAR_guardduty_malware_protection_role_arns, not in this file.
# No wildcard, and every ARN must belong to this account. Procedure: docs/runbooks/foundation-second-apply.md.
# guardduty_malware_protection_role_arns = ["arn:aws:iam::<account-id>:role/<scan-role>"]

# API Gateway CloudWatch role: the setting is unique per account and region, and dev and prod share the workshop
# account (ADR-0002). Managed by dev only.
manage_api_gateway_account = true

# Alerts when a domain key is disabled, scheduled for deletion, loses rotation or alias, or has its policy rewritten.
enable_deletion_alerts = true

# The workshop IAM role is denied budgets:* (the apply would fail with Access Denied): the budget stays off.
# To enable it in an account that allows AWS Budgets, also set budget_monthly_limit_usd (and TF_VAR_budget_notification_emails).
enable_budget = false
