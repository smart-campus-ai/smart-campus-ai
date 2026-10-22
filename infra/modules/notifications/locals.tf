data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  # SES publishes configuration set events to the ops topic as a service principal, scoped to the configuration set.
  ses_event_services = { for s in toset(var.enable_configuration_set ? ["ses.amazonaws.com"] : []) : s => aws_sesv2_configuration_set.this[*].arn }

  topics = {
    admins = {
      name           = "${var.name_prefix}-admins"
      principal_arns = var.admins_publishers.principal_arns
      services       = var.admins_publishers.services
    }
    ops = {
      name           = "${var.name_prefix}-ops"
      principal_arns = var.ops_publishers.principal_arns
      services       = merge(var.ops_publishers.services, local.ses_event_services)
    }
  }

  # PII handling. Sender, recipient and subscription addresses come from sensitive variables, so every value derived
  # from them is sensitive. for_each keys cannot be sensitive: each collection is therefore keyed by a hash of the
  # address (non-sensitive, stable, no address in resource addresses or plan output) and the resources read the
  # sensitive value through that key. nonsensitive() is applied to the hashes only, never to an address.
  has_sender_email  = nonsensitive(var.sender_email_address != null)
  has_sender_domain = var.sender_domain != null

  sender_email_address = var.sender_email_address == null ? null : lower(var.sender_email_address)
  sender_domain        = var.sender_domain == null ? null : lower(var.sender_domain)

  # ses:FromAddress patterns the notifier may use: the sender address, and any address of the sender domain.
  sender_from_patterns = concat(
    local.has_sender_email ? [local.sender_email_address] : [],
    local.has_sender_domain ? ["*@${local.sender_domain}"] : [],
  )

  recipient_identities = {
    for e in distinct([for raw in var.recipient_email_identities : lower(raw)]) :
    substr(sha256("${var.name_prefix}:recipient:${e}"), 0, 16) => e
    if e != local.sender_email_address
  }
  recipient_identity_keys = toset(nonsensitive(keys(local.recipient_identities)))

  subscription_endpoints = merge(
    { for e in distinct([for raw in var.admins_email_endpoints : lower(raw)]) : "admins-${substr(sha256("${var.name_prefix}:admins:${e}"), 0, 16)}" => e },
    { for e in distinct([for raw in var.ops_email_endpoints : lower(raw)]) : "ops-${substr(sha256("${var.name_prefix}:ops:${e}"), 0, 16)}" => e },
  )
  subscription_keys = toset(nonsensitive(keys(local.subscription_endpoints)))

  configuration_set_name = "${var.name_prefix}-ses"
}
