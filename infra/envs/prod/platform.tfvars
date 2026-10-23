env         = "prod"
name_prefix = "sc-prod"

# Not stored here, passed through the environment (CI variables or secrets):
#   TF_VAR_state_kms_key_arn         bootstrap output state_kms_key_arn
#   TF_VAR_permissions_boundary_arn  bootstrap output workload_boundary_arns["prod"] (blocked by issue #98)
#   TF_VAR_sender_email_address      SES sender (PII); or set sender_domain and sender_local_parts below
#   TF_VAR_recipient_email_identities, TF_VAR_admins_email_endpoints, TF_VAR_ops_email_endpoints   (PII, optional)

log_retention_in_days      = 90
enable_deletion_protection = true

# Runtime chosen by SE: to confirm (the code is deployed by the application pipeline).
lambda_runtime = "python3.13"

api_throttling_rate_limit  = 100
api_throttling_burst_limit = 200
api_method_throttling = {
  "api/chat/POST"    = { rate_limit = 10, burst_limit = 20 }
  "api/tickets/POST" = { rate_limit = 10, burst_limit = 20 }
}

# RF04: both web ACLs on (required in prod). Rate limits per 300 s window: per IP (shared campus NAT) and per user
# (Authorization header).
enable_waf                       = true
waf_rate_limit_per_ip            = 2000
waf_rate_limit_per_authorization = 1000

local_origins = []

# Retentions to validate with the PO and the BA (US08).
chat_retention_days        = 30
attachments_retention_days = 365

# Malware protection is mandatory in prod (the stack refuses false): unscanned attachments are never served. Prod is not
# deployed during the workshop (ADR-0002), so the GuardDuty Malware Protection for S3 availability (EN-11) does not
# block anything yet; confirm it before the first prod apply.
enable_malware_protection = true

# The knowledge base stays off until EN-11 confirms Bedrock Knowledge Bases and S3 Vectors. Switch it on before real data
# reaches prod (see the comment of enable_knowledge_base in dev for the extra variables).
enable_knowledge_base = false
