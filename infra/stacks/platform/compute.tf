# One lambda-service per bounded use case: arm64, one execution role each (with the permissions boundary), explicit
# KMS-encrypted log group, active tracing, alias "live" (the only target of the integrations). The infrastructure owns
# the configuration, the application pipeline owns the code (placeholder archive on the first apply).
#
# The data access of each function is its extra_policy_json, built in iam.tf from the policy documents of the producer
# modules. Functions invoked asynchronously (escalation, notifier, kb-sync, kpi-aggregator) get an SQS dead-letter
# queue encrypted with the data key.

locals {
  # Present only when the knowledge base exists. The identifiers also reach kb-sync, through SSM (see locals.tf).
  chat_knowledge_base_environment = var.enable_knowledge_base ? {
    KNOWLEDGE_BASE_ID = module.knowledge_base[0].knowledge_base_id
    CHAT_MODEL_ID     = var.chat_inference_profile_id
  } : {}
}

module "tickets" {
  source = "../../modules/lambda-service"

  name_prefix   = var.name_prefix
  function_name = "tickets"
  description   = "Ticket lifecycle: create, read, update, attachments (presigned POST) and SLA schedule."
  runtime       = var.lambda_runtime
  handler       = var.lambda_handler

  permissions_boundary_arn = var.permissions_boundary_arn
  environment_kms_key_arn  = local.kms_key_arns["data"]
  logs_kms_key_arn         = local.kms_key_arns["logs"]
  log_retention_in_days    = var.log_retention_in_days
  extra_policy_json        = data.aws_iam_policy_document.tickets_function.json

  environment_variables = {
    TICKETS_TABLE             = module.tickets_store.table_name
    TICKETS_OWNER_INDEX       = module.tickets_store.owner_index_name
    TICKETS_STATUS_INDEX      = module.tickets_store.status_index_name
    ATTACHMENTS_BUCKET        = module.attachments_bucket.bucket_name
    ATTACHMENTS_PREFIX        = module.attachments_bucket.attachments_prefix
    ATTACHMENTS_MAX_BYTES     = tostring(module.attachments_bucket.max_upload_bytes)
    ATTACHMENTS_CONTENT_TYPES = join(",", module.attachments_bucket.allowed_content_types)
    ADMINS_TOPIC_ARN          = module.notifications.admins_topic_arn
    SLA_SCHEDULE_GROUP        = module.sla_scheduler.schedule_group_name
    SLA_SCHEDULER_ROLE_ARN    = module.sla_scheduler.scheduler_role_arn
    SLA_TARGET_ARN            = module.escalation.alias_arn
    SLA_DLQ_ARN               = module.sla_scheduler.dlq_arn
  }
}

module "kpi" {
  source = "../../modules/lambda-service"

  name_prefix   = var.name_prefix
  function_name = "kpi"
  description   = "KPI dashboard read model (administrators only)."
  runtime       = var.lambda_runtime
  handler       = var.lambda_handler

  permissions_boundary_arn = var.permissions_boundary_arn
  environment_kms_key_arn  = local.kms_key_arns["data"]
  logs_kms_key_arn         = local.kms_key_arns["logs"]
  log_retention_in_days    = var.log_retention_in_days

  # TODO(kpi): KPI_TABLE and the read policy on the kpi table, once the kpi module is merged.
}

module "chat" {
  source = "../../modules/lambda-service"

  name_prefix   = var.name_prefix
  function_name = "chat"
  description   = "RAG assistant: chat sessions, knowledge base retrieval, guardrail."
  runtime       = var.lambda_runtime
  handler       = var.lambda_handler
  memory_size   = 512
  timeout       = 28

  permissions_boundary_arn = var.permissions_boundary_arn
  environment_kms_key_arn  = local.kms_key_arns["data"]
  logs_kms_key_arn         = local.kms_key_arns["logs"]
  log_retention_in_days    = var.log_retention_in_days
  extra_policy_json        = data.aws_iam_policy_document.chat_function.json

  environment_variables = merge(
    {
      CHAT_SESSIONS_TABLE         = module.chat_sessions.table_name
      CHAT_SESSIONS_OWNER_INDEX   = module.chat_sessions.owner_index_name
      CHAT_SESSIONS_TTL_ATTRIBUTE = module.chat_sessions.ttl_attribute_name
      CHAT_RETENTION_DAYS         = tostring(module.chat_sessions.retention_days)
      GUARDRAIL_ID                = module.bedrock_guardrail.guardrail_id
      GUARDRAIL_VERSION           = module.bedrock_guardrail.guardrail_version
    },
    local.chat_knowledge_base_environment,
  )
}

module "escalation" {
  source = "../../modules/lambda-service"

  name_prefix   = var.name_prefix
  function_name = "escalation"
  description   = "SLA escalation, invoked once per ticket by EventBridge Scheduler (idempotent)."
  runtime       = var.lambda_runtime
  handler       = var.lambda_handler

  permissions_boundary_arn = var.permissions_boundary_arn
  environment_kms_key_arn  = local.kms_key_arns["data"]
  logs_kms_key_arn         = local.kms_key_arns["logs"]
  log_retention_in_days    = var.log_retention_in_days
  extra_policy_json        = data.aws_iam_policy_document.escalation_function.json
  enable_dlq               = true
  dlq_kms_key_arn          = local.kms_key_arns["data"]

  environment_variables = {
    TICKETS_TABLE    = module.tickets_store.table_name
    ADMINS_TOPIC_ARN = module.notifications.admins_topic_arn
  }
}

module "notifier" {
  source = "../../modules/lambda-service"

  name_prefix   = var.name_prefix
  function_name = "notifier"
  description   = "E-mail notifications to students, from the tickets stream."
  runtime       = var.lambda_runtime
  handler       = var.lambda_handler

  permissions_boundary_arn = var.permissions_boundary_arn
  environment_kms_key_arn  = local.kms_key_arns["data"]
  logs_kms_key_arn         = local.kms_key_arns["logs"]
  log_retention_in_days    = var.log_retention_in_days
  extra_policy_json        = module.notifications.send_email_policy_json
  enable_dlq               = true
  dlq_kms_key_arn          = local.kms_key_arns["data"]

  # TODO(notifier): tickets stream event source mapping (event filters, batch item failures, bisect on error, SQS
  # on-failure destination) with the stream read policy, and the sender address (PII) read from SSM at runtime.
}

module "kb_sync" {
  source = "../../modules/lambda-service"

  name_prefix   = var.name_prefix
  function_name = "kb-sync"
  description   = "Starts a knowledge base ingestion job when a source document changes."
  runtime       = var.lambda_runtime
  handler       = var.lambda_handler

  permissions_boundary_arn = var.permissions_boundary_arn
  environment_kms_key_arn  = local.kms_key_arns["data"]
  logs_kms_key_arn         = local.kms_key_arns["logs"]
  log_retention_in_days    = var.log_retention_in_days
  extra_policy_json        = data.aws_iam_policy_document.kb_sync_function.json
  enable_dlq               = true
  dlq_kms_key_arn          = local.kms_key_arns["data"]

  environment_variables = {
    KNOWLEDGE_BASE_ID_SSM_PARAMETER = local.kb_sync_parameter_names.knowledge_base_id
    DATA_SOURCE_ID_SSM_PARAMETER    = local.kb_sync_parameter_names.data_source_id
  }
}

module "kpi_aggregator" {
  source = "../../modules/lambda-service"

  name_prefix   = var.name_prefix
  function_name = "kpi-aggregator"
  description   = "Daily KPI aggregates, maintained from the tickets stream."
  runtime       = var.lambda_runtime
  handler       = var.lambda_handler

  permissions_boundary_arn = var.permissions_boundary_arn
  environment_kms_key_arn  = local.kms_key_arns["data"]
  logs_kms_key_arn         = local.kms_key_arns["logs"]
  log_retention_in_days    = var.log_retention_in_days
  enable_dlq               = true
  dlq_kms_key_arn          = local.kms_key_arns["data"]

  # TODO(kpi): KPI_TABLE, the write policy on the kpi table and the tickets stream event source mapping, once the kpi
  # module is merged.
}

module "pre_token" {
  source = "../../modules/lambda-service"

  name_prefix   = var.name_prefix
  function_name = "pre-token"
  description   = "Cognito pre-token generation trigger: approved e-mail domain and group mapping."
  runtime       = var.lambda_runtime
  handler       = var.lambda_handler

  permissions_boundary_arn = var.permissions_boundary_arn
  environment_kms_key_arn  = local.kms_key_arns["data"]
  logs_kms_key_arn         = local.kms_key_arns["logs"]
  log_retention_in_days    = var.log_retention_in_days

  # TODO(US06): approved e-mail domains, lambda permission for cognito-idp (SourceArn = user pool) and the trigger on
  # the user pool, once the identity module accepts a pre-token Lambda.
}
