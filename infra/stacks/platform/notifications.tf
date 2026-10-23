# SNS topics (admins, ops) and SES sender identity. SES is in the sandbox during the workshop: every recipient must be a
# verified identity (recipient_email_identities).
#
# The tickets and escalation roles publish to the admins topic. Both the topic policy (principal_arns) and the
# identity policies of the roles (iam.tf) grant it; the topic depends on the roles, never the other way round.
module "notifications" {
  source = "../../modules/notifications"

  name_prefix = var.name_prefix
  kms_key_arn = local.kms_key_arns["data"]

  sender_email_address       = var.sender_email_address
  sender_domain              = var.sender_domain
  sender_local_parts         = var.sender_local_parts
  recipient_email_identities = var.recipient_email_identities
  admins_email_endpoints     = var.admins_email_endpoints
  ops_email_endpoints        = var.ops_email_endpoints

  admins_publishers = {
    principal_arns = [module.tickets.role_arn, module.escalation.role_arn]
  }

  # TODO(observability, budget): ops_publishers = cloudwatch.amazonaws.com (alarm ARNs of the environment) and
  # budgets.amazonaws.com (budget ARNs), once those modules are merged.
}
