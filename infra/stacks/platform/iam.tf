# Least-privilege policy documents of the functions (lambda-service extra_policy_json): the producer documents (chat
# sessions, attachments, knowledge base) merged with the statements that no producer module publishes. One document
# per function, so that no function depends on the resources of another (a shared local would link them all).
# Statement IDs must be unique inside one merged document.

# tickets table access of "tickets" and "escalation": items by key and Query on the table and its indexes. No Scan.
data "aws_iam_policy_document" "tickets_table" {
  statement {
    sid       = "TicketsTableItems"
    effect    = "Allow"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem"]
    resources = [module.tickets_store.table_arn]
  }

  statement {
    sid       = "TicketsTableQuery"
    effect    = "Allow"
    actions   = ["dynamodb:Query"]
    resources = concat([module.tickets_store.table_arn], values(module.tickets_store.index_arns))
  }
}

# "tickets" signs the presigned POST and GET of the attachments (S3 bucket encrypted with the data key) and publishes
# the alerts of security tickets to the admins topic (encrypted with the data key). The key is usable through these two
# services only.
data "aws_iam_policy_document" "tickets_function" {
  source_policy_documents = [
    data.aws_iam_policy_document.tickets_table.json,
    module.attachments_bucket.policy_json_tickets_rw,
  ]

  statement {
    sid       = "UseDataKeyForAttachmentsAndAlerts"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [local.kms_key_arns["data"]]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${local.region}.amazonaws.com", "sns.${local.region}.amazonaws.com"]
    }
  }

  statement {
    sid       = "PublishAdminAlerts"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [module.notifications.admins_topic_arn]
  }
}

# "escalation" updates the ticket and publishes the SLA alerts to the admins topic.
data "aws_iam_policy_document" "escalation_function" {
  source_policy_documents = [data.aws_iam_policy_document.tickets_table.json]

  statement {
    sid       = "UseDataKeyForAlerts"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [local.kms_key_arns["data"]]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["sns.${local.region}.amazonaws.com"]
    }
  }

  statement {
    sid       = "PublishAdminAlerts"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [module.notifications.admins_topic_arn]
  }
}

# "chat" uses its sessions table, applies the guardrail and, when the knowledge base exists, retrieves from it and
# invokes the inference profile.
data "aws_iam_policy_document" "chat_function" {
  source_policy_documents = concat(
    [module.chat_sessions.access_policy_json],
    module.knowledge_base[*].policy_json_retrieve,
  )

  statement {
    sid       = "ApplyGuardrail"
    effect    = "Allow"
    actions   = ["bedrock:ApplyGuardrail"]
    resources = [module.bedrock_guardrail.guardrail_arn]
  }
}

# "kb-sync" reads the knowledge base identifiers published in ssm.tf. Its ingestion policy is attached below.
data "aws_iam_policy_document" "kb_sync_function" {
  statement {
    sid       = "ReadKnowledgeBaseIdentifiers"
    effect    = "Allow"
    actions   = ["ssm:GetParameter"]
    resources = [for name in values(local.kb_sync_parameter_names) : "arn:${local.partition}:ssm:${local.region}:${local.account_id}:parameter${name}"]
  }
}

# Attached here and not through lambda-service extra_policy_json: that input refuses iam:PassRole by design. The
# document comes from the sla-scheduler module and allows PassRole on the scheduler execution role only, to
# scheduler.amazonaws.com only, plus CreateSchedule and DeleteSchedule on the SLA group schedules.
resource "aws_iam_role_policy" "tickets_schedules" {
  name   = "${var.name_prefix}-tickets-schedules"
  role   = module.tickets.role_name
  policy = module.sla_scheduler.tickets_schedules_policy_json
}

# Attached here and not through lambda-service extra_policy_json: the knowledge base depends on the kb-sync alias (S3
# notification), so kb-sync cannot take the knowledge base policy as an input without a dependency cycle.
resource "aws_iam_role_policy" "kb_sync_ingestion" {
  count = var.enable_knowledge_base ? 1 : 0

  name   = "${var.name_prefix}-kb-sync-ingestion"
  role   = module.kb_sync.role_name
  policy = module.knowledge_base[0].policy_json_sync
}
