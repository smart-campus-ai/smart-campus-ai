# Sender identities (AC1): an e-mail address, a domain, or both. SES sends a verification mail to an address; a domain
# is verified through DKIM CNAME records (see the ses_domain_dkim_tokens output) that the owner publishes in DNS.
# "No custom domain" (ADR-0003) only concerns the application URL, not the mail sender domain.
# SES sandbox: until production access is granted, every recipient must also be a verified identity
# (recipient_email_identities) and the daily quota is 200 messages.
resource "aws_sesv2_email_identity" "sender" {
  count = local.has_sender_email ? 1 : 0

  email_identity         = local.sender_email_address
  configuration_set_name = one(aws_sesv2_configuration_set.this[*].configuration_set_name)

  tags = merge(var.tags, { Name = "${var.name_prefix}-ses-sender" })
}

resource "aws_sesv2_email_identity" "sender_domain" {
  count = local.has_sender_domain ? 1 : 0

  email_identity         = local.sender_domain
  configuration_set_name = one(aws_sesv2_configuration_set.this[*].configuration_set_name)

  tags = merge(var.tags, { Name = "${var.name_prefix}-ses-sender-domain" })
}

resource "aws_sesv2_email_identity" "recipient" {
  for_each = local.recipient_identity_keys

  email_identity = local.recipient_identities[each.key]

  tags = merge(var.tags, { Name = "${var.name_prefix}-ses-recipient" })
}

resource "aws_sesv2_configuration_set" "this" {
  count = var.enable_configuration_set ? 1 : 0

  configuration_set_name = local.configuration_set_name

  delivery_options {
    tls_policy = "REQUIRE"
  }

  reputation_options {
    reputation_metrics_enabled = true
  }

  sending_options {
    sending_enabled = true
  }

  suppression_options {
    suppressed_reasons = ["BOUNCE", "COMPLAINT"]
  }

  tags = merge(var.tags, { Name = local.configuration_set_name })
}

# SES needs the ops topic policy (ses.amazonaws.com scoped to the configuration set) before it can publish.
resource "aws_sesv2_configuration_set_event_destination" "ops" {
  count = var.enable_configuration_set ? 1 : 0

  configuration_set_name = aws_sesv2_configuration_set.this[0].configuration_set_name
  event_destination_name = "${var.name_prefix}-ops"

  event_destination {
    enabled              = true
    matching_event_types = var.configuration_set_event_types

    sns_destination {
      topic_arn = aws_sns_topic.this["ops"].arn
    }
  }

  depends_on = [aws_sns_topic_policy.this]
}

# Identity-based policy for the sender (attached by the stack to the notifier role). ses:SendEmail is limited to the
# sender identity ARN(s) and to the From addresses of those identities (ses:FromAddress).
# The configuration set is not a resource of this statement by default: SES has no condition key that pins the
# configuration set on SendEmail, so it is enforced by the identity instead. Both sender identities carry the
# configuration set as their default (configuration_set_name), which SES applies to every message sent from them.
# Because the configuration-set ARN is not granted, a call that names another configuration set is denied.
# If SES turns out to evaluate IAM on the default configuration set, enable_configuration_set_grant adds its exact ARN.
# ses:FromAddress values are exact (sender address, <local part>@<sender domain>), never a domain wildcard.
data "aws_iam_policy_document" "send_email" {
  statement {
    sid     = "SendEmailFromSenderIdentity"
    effect  = "Allow"
    actions = ["ses:SendEmail"]
    resources = concat(
      aws_sesv2_email_identity.sender[*].arn,
      aws_sesv2_email_identity.sender_domain[*].arn,
      var.enable_configuration_set_grant ? aws_sesv2_configuration_set.this[*].arn : [],
    )

    condition {
      test     = "StringEquals"
      variable = "ses:FromAddress"
      values   = local.sender_from_addresses
    }
  }
}
