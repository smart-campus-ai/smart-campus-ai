env         = "dev"
name_prefix = "sc-dev"

# state_kms_key_arn (bootstrap output) is not stored here: pass TF_VAR_state_kms_key_arn or -var.
# admin_principal_arns is not stored here either (account ID and break-glass role names stay out of the repository):
#   TF_VAR_admin_principal_arns='["arn:aws:iam::<account-id>:role/<bootstrap-admin-role>","arn:aws:iam::<account-id>:role/<break-glass-role>"]'
# It must include the identity that runs the apply creating the keys, and never a CI role.

kms_deletion_window_in_days = 7

# Bedrock may use the ai key for the Knowledge Bases of the account, so the platform stack can create one at first apply.
enable_bedrock = true

# Producers of these grants live in the platform stack. Leave them empty at the first apply; once platform exists, apply
# foundation again with the distribution ARN and the scan role ARNs (platform outputs). The ARNs carry the account ID, so
# pass them as TF_VAR_cloudfront_distribution_arns / TF_VAR_guardduty_malware_protection_role_arns, not in this file.
# No wildcard, and every ARN must belong to this account. Procedure: docs/runbooks/foundation-second-apply.md.
# cloudfront_distribution_arns           = ["arn:aws:cloudfront::<account-id>:distribution/<id>"]
# guardduty_malware_protection_role_arns = ["arn:aws:iam::<account-id>:role/<scan-role>"]

# Alerts when a domain key is disabled, scheduled for deletion, loses rotation or alias, or has its policy rewritten.
enable_deletion_alerts = true

# The workshop IAM role is denied budgets:* (the apply would fail with Access Denied): the budget stays off.
# To enable it in an account that allows AWS Budgets, also set budget_monthly_limit_usd (and TF_VAR_budget_notification_emails).
enable_budget = false

# ADR-0014 (option B, accepted): the workshop account cannot attach permissions boundaries (no iam:PutRolePermissionsBoundary).
# The exception is limited to this account and expires at the end of the workshop; after that day the plan fails.
# To return to the full invariant: enable_permissions_boundaries = true and pass workload_boundary_arn.
enable_permissions_boundaries  = false
boundary_exception_account_ids = ["762233769579"]
boundary_exception_expires     = "2026-10-31"
