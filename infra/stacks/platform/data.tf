# Data stores: tickets table, kpi table (daily aggregates), chat sessions table (separate retention, GDPR TTL) and the
# attachments bucket.
module "tickets_store" {
  source = "../../modules/tickets-store"

  name_prefix                = var.name_prefix
  kms_key_arn                = local.kms_key_arns["data"]
  enable_deletion_protection = var.enable_deletion_protection
}

# kpi table, failure queue and tickets stream -> kpi-aggregator mapping. The aggregator access policy is attached to the
# function role in iam.tf (aws_iam_role_policy_attachment.kpi_aggregator); function_name comes from the terraform_data
# that waits for that attachment, so the mapping is created after the IAM policy.
module "kpi_store" {
  source = "../../modules/kpi"

  name_prefix                = var.name_prefix
  kms_key_arn                = local.kms_key_arns["data"]
  enable_deletion_protection = var.enable_deletion_protection
  stream_arn                 = module.tickets_store.stream_arn
  function_name              = terraform_data.kpi_aggregator_iam_ready.output
  aggregator_role_arn        = module.kpi_aggregator.role_arn
}

module "chat_sessions" {
  source = "../../modules/chat-sessions"

  name_prefix                 = var.name_prefix
  kms_key_arn                 = local.kms_key_arns["data"]
  deletion_protection_enabled = var.enable_deletion_protection
  retention_days              = var.chat_retention_days
}

# The CORS origins are the site URL (and the local origins in dev). Only the CORS rule of the module reads them, not the
# bucket nor the "tickets" policy, so there is no cycle through attachments -> site -> api -> tickets -> attachments.
module "attachments_bucket" {
  source = "../../modules/attachments-bucket"

  name_prefix               = var.name_prefix
  kms_key_arn               = local.kms_key_arns["data"]
  allowed_origins           = concat([module.static_site.site_url], var.local_origins)
  object_expiration_days    = var.attachments_retention_days
  enable_malware_protection = var.enable_malware_protection
  permissions_boundary_arn  = var.permissions_boundary_arn
}
