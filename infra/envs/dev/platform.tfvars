env         = "dev"
name_prefix = "sc-dev"

# Not stored here, passed through the environment (CI variables or secrets):
#   TF_VAR_state_kms_key_arn         bootstrap output state_kms_key_arn
#   TF_VAR_workload_boundary_arn     bootstrap output workload_boundary_arns["dev"] (only when enable_permissions_boundaries = true)
#   TF_VAR_sender_email_address      SES sender (PII); or set sender_domain and sender_local_parts below
#   TF_VAR_recipient_email_identities, TF_VAR_admins_email_endpoints, TF_VAR_ops_email_endpoints   (PII, optional)

log_retention_in_days      = 14
enable_deletion_protection = false

# Runtime chosen by SE: to confirm (the code is deployed by the application pipeline).
lambda_runtime = "python3.13"

api_throttling_rate_limit  = 50
api_throttling_burst_limit = 100
api_method_throttling = {
  "api/chat/POST"    = { rate_limit = 5, burst_limit = 10 }
  "api/tickets/POST" = { rate_limit = 5, burst_limit = 10 }
}

# RF04: both web ACLs on. Rate limits per 300 s window: per IP (shared campus NAT) and per user (Authorization header).
enable_waf                       = true
waf_rate_limit_per_ip            = 1000
waf_rate_limit_per_authorization = 500

local_origins = ["http://localhost:5173"]

# Retentions to validate with the PO and the BA (US08).
chat_retention_days        = 30
attachments_retention_days = 30

# Workshop dev account: GuardDuty Malware Protection for S3 is not enabled for the attachments (EN-11).
enable_malware_protection = false

# Knowledge base disabled in dev. To enable it, also set knowledge_base_writer_principal_arns, chat_foundation_model_id,
# chat_inference_profile_id (us.* in the workshop, ADR-0013) and chat_inference_regions.
enable_knowledge_base = false

# ADR-0014 (option B, accepted): the workshop account cannot attach permissions boundaries (no iam:PutRolePermissionsBoundary).
# The exception is limited to this account and expires at the end of the workshop; after that day the plan fails.
# To return to the full invariant: enable_permissions_boundaries = true and pass workload_boundary_arn.
enable_permissions_boundaries  = false
boundary_exception_account_ids = ["762233769579"]
boundary_exception_expires     = "2026-10-31"
