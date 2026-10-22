mock_provider "aws" {
  # Fake documentation account ID, used only to keep conditions predictable.
  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
    }
  }

  # The mock returns random strings for computed attributes, which aws_sns_topic_policy.policy rejects as invalid JSON.
  # The invariants are asserted on the document arguments (known at plan), not on the JSON.
  override_data {
    target = data.aws_iam_policy_document.topic
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.send_email
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  # Computed ARNs are consumed by policies, subscriptions and the event destination.
  override_resource {
    target = aws_sns_topic.this
    values = {
      arn = "arn:aws:sns:us-east-1:123456789012:sc-dev-topic"
    }
  }

  override_resource {
    target = aws_sesv2_email_identity.sender
    values = {
      arn = "arn:aws:ses:us-east-1:123456789012:identity/noreply@example.com"
    }
  }

  override_resource {
    target = aws_sesv2_email_identity.sender_domain
    values = {
      arn = "arn:aws:ses:us-east-1:123456789012:identity/mail.example.org"
    }
  }

  override_resource {
    target = aws_sesv2_configuration_set.this
    values = {
      arn = "arn:aws:ses:us-east-1:123456789012:configuration-set/sc-dev-ses"
    }
  }
}

variables {
  name_prefix = "sc-dev"
  kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
  # Placeholder addresses on the reserved example.com domain.
  sender_email_address = "noreply@example.com"

  admins_publishers = {
    principal_arns = [
      "arn:aws:iam::123456789012:role/sc-dev-tickets",
      "arn:aws:iam::123456789012:role/sc-dev-escalation",
    ]
  }

  ops_publishers = {
    services = {
      "cloudwatch.amazonaws.com" = ["arn:aws:cloudwatch:us-east-1:123456789012:alarm:sc-dev-*"]
      "budgets.amazonaws.com"    = ["arn:aws:budgets::123456789012:budget/sc-dev-*"]
    }
  }
}

# EN45-AC1: a sender e-mail address identity is created, and no domain identity unless asked
run "en45_ac1_sender_email_identity_created" {
  command = plan

  variables {
    sender_email_address = "NoReply@Example.com"
  }

  assert {
    condition     = length(aws_sesv2_email_identity.sender) == 1 && aws_sesv2_email_identity.sender[0].email_identity == "noreply@example.com"
    error_message = "The sender identity must be the (lower-cased) sender e-mail address."
  }

  assert {
    condition     = length(aws_sesv2_email_identity.sender_domain) == 0
    error_message = "No domain identity must exist unless sender_domain is set."
  }

  assert {
    condition     = length(aws_sesv2_email_identity.recipient) == 0
    error_message = "No recipient identity must exist by default."
  }
}

# EN45-AC1: a domain identity is supported on its own
run "en45_ac1_sender_domain_identity_only" {
  command = plan

  variables {
    sender_email_address = null
    sender_domain        = "Mail.Example.org"
  }

  assert {
    condition     = length(aws_sesv2_email_identity.sender) == 0
    error_message = "No e-mail identity must exist when only a domain is supplied."
  }

  assert {
    condition     = length(aws_sesv2_email_identity.sender_domain) == 1 && aws_sesv2_email_identity.sender_domain[0].email_identity == "mail.example.org"
    error_message = "The sender identity must be the (lower-cased) sender domain."
  }
}

# EN45-AC1: e-mail and domain identities can be combined
run "en45_ac1_sender_email_and_domain_identities" {
  command = plan

  variables {
    sender_domain = "mail.example.org"
  }

  assert {
    condition     = length(aws_sesv2_email_identity.sender) == 1 && length(aws_sesv2_email_identity.sender_domain) == 1
    error_message = "Both the e-mail and the domain identity must be created when both are supplied."
  }
}

# EN45-AC1: at least one sender identity is required
run "en45_ac1_rejects_missing_sender_identity" {
  command = plan

  variables {
    sender_email_address = null
    sender_domain        = null
  }

  expect_failures = [var.sender_domain]
}

# EN45-AC1: rejects an invalid sender domain
run "en45_ac1_rejects_invalid_sender_domain" {
  command = plan

  variables {
    sender_domain = "not a domain"
  }

  expect_failures = [var.sender_domain]
}

# EN45-AC1: recipient identities are deduplicated and exclude the sender
run "en45_ac1_recipient_identities_created" {
  command = plan

  variables {
    recipient_email_identities = ["alice@example.com", "Alice@example.com", "noreply@example.com", "bob@example.com"]
  }

  assert {
    condition     = toset([for i in values(aws_sesv2_email_identity.recipient) : i.email_identity]) == toset(["alice@example.com", "bob@example.com"])
    error_message = "Recipient identities must be deduplicated and must not repeat the sender."
  }

  assert {
    condition     = alltrue([for k in keys(aws_sesv2_email_identity.recipient) : !can(regex("@", k))])
    error_message = "Resource keys must not contain e-mail addresses."
  }
}

# EN45-AC1: PII inputs are sensitive so addresses never appear in plan output
run "en45_ac1_pii_inputs_are_sensitive" {
  command = plan

  assert {
    condition = alltrue([
      for v in [var.sender_email_address, var.recipient_email_identities, var.admins_email_endpoints, var.ops_email_endpoints] :
      issensitive(v)
    ])
    error_message = "Sender, recipient and subscription addresses must be sensitive variables."
  }
}

# EN45-AC1: the configuration set is optional and off by default
run "en45_ac1_configuration_set_off_by_default" {
  command = plan

  assert {
    condition     = length(aws_sesv2_configuration_set.this) == 0 && length(aws_sesv2_configuration_set_event_destination.ops) == 0
    error_message = "No configuration set or event destination must exist unless enabled."
  }

  assert {
    condition     = aws_sesv2_email_identity.sender[0].configuration_set_name == null
    error_message = "The sender identity must not reference a configuration set when disabled."
  }
}

# EN45-AC1: the configuration set requires TLS and publishes delivery problems to the ops topic
run "en45_ac1_configuration_set_publishes_to_ops" {
  command = plan

  variables {
    enable_configuration_set = true
  }

  assert {
    condition     = aws_sesv2_configuration_set.this[0].configuration_set_name == "sc-dev-ses"
    error_message = "The configuration set must be named <prefix>-ses."
  }

  assert {
    condition     = one(aws_sesv2_configuration_set.this[0].delivery_options).tls_policy == "REQUIRE"
    error_message = "The configuration set must require TLS."
  }

  assert {
    condition     = one(aws_sesv2_configuration_set.this[0].reputation_options).reputation_metrics_enabled == true
    error_message = "Reputation metrics must be enabled."
  }

  assert {
    condition     = toset(one(aws_sesv2_configuration_set_event_destination.ops[0].event_destination).matching_event_types) == toset(["BOUNCE", "COMPLAINT", "REJECT", "RENDERING_FAILURE"])
    error_message = "The event destination must publish bounces, complaints, rejects and rendering failures by default."
  }

  assert {
    condition     = one(one(aws_sesv2_configuration_set_event_destination.ops[0].event_destination).sns_destination).topic_arn == aws_sns_topic.this["ops"].arn
    error_message = "The event destination must target the ops topic."
  }

  assert {
    condition     = aws_sesv2_email_identity.sender[0].configuration_set_name == "sc-dev-ses"
    error_message = "The sender identity must use the configuration set by default."
  }
}

# EN45-AC1: rejects an invalid sender address
run "en45_ac1_rejects_invalid_sender" {
  command = plan

  variables {
    sender_email_address = "example.com"
  }

  expect_failures = [var.sender_email_address]
}

# EN45-AC1: rejects an invalid recipient identity
run "en45_ac1_rejects_invalid_recipient_identity" {
  command = plan

  variables {
    recipient_email_identities = ["not-an-address"]
  }

  expect_failures = [var.recipient_email_identities]
}

# EN45-AC1: rejects an unknown SES event type
run "en45_ac1_rejects_unknown_event_type" {
  command = plan

  variables {
    configuration_set_event_types = ["BOUNCE", "EXPLODE"]
  }

  expect_failures = [var.configuration_set_event_types]
}

# EN45-AC2: admins and ops topics exist and are encrypted with the KMS input key
run "en45_ac2_topics_encrypted_with_kms_key" {
  command = plan

  assert {
    condition     = toset(keys(aws_sns_topic.this)) == toset(["admins", "ops"])
    error_message = "Exactly the admins and ops topics must exist."
  }

  assert {
    condition     = aws_sns_topic.this["admins"].name == "sc-dev-admins" && aws_sns_topic.this["ops"].name == "sc-dev-ops"
    error_message = "Topics must be named <prefix>-admins and <prefix>-ops."
  }

  assert {
    condition     = alltrue([for t in values(aws_sns_topic.this) : t.kms_master_key_id == var.kms_key_arn])
    error_message = "Every topic must be encrypted with kms_key_arn."
  }

  assert {
    condition     = alltrue([for t in values(aws_sns_topic.this) : t.signature_version == 2])
    error_message = "Topics must sign messages with signature version 2."
  }

  assert {
    condition     = toset(keys(aws_sns_topic_policy.this)) == toset(["admins", "ops"])
    error_message = "Every topic must have an explicit policy."
  }
}

# EN45-AC2: tags are merged on topics
run "en45_ac2_topics_carry_extra_tags" {
  command = plan

  variables {
    tags = { Owner = "ops" }
  }

  assert {
    condition     = alltrue([for t in values(aws_sns_topic.this) : t.tags["Owner"] == "ops"])
    error_message = "Extra tags must be applied to the topics."
  }
}

# EN45-AC2: rejects a KMS alias instead of a key ARN
run "en45_ac2_rejects_kms_alias" {
  command = plan

  variables {
    kms_key_arn = "alias/sc-dev-data"
  }

  expect_failures = [var.kms_key_arn]
}

# EN45-AC2: rejects an invalid name_prefix
run "en45_ac2_rejects_invalid_name_prefix" {
  command = plan

  variables {
    name_prefix = "Bad_Prefix"
  }

  expect_failures = [var.name_prefix]
}

# EN45-AC3: every topic policy denies requests without TLS
run "en45_ac3_policies_deny_insecure_transport" {
  command = plan

  assert {
    condition = alltrue([
      for k in ["admins", "ops"] : anytrue([
        for s in data.aws_iam_policy_document.topic[k].statement :
        s.sid == "DenyInsecureTransport" && s.effect == "Deny" &&
        toset(s.actions) == toset(["sns:*"]) &&
        toset(s.resources) == toset([aws_sns_topic.this[k].arn]) &&
        alltrue([for p in s.principals : p.type == "AWS" && toset(p.identifiers) == toset(["*"])]) &&
        anytrue([
          for c in s.condition :
          c.variable == "aws:SecureTransport" && c.test == "Bool" && toset(c.values) == toset(["false"])
        ])
      ])
    ])
    error_message = "Every topic policy must deny every sns:* action on the topic without aws:SecureTransport."
  }

  # The wildcard is only acceptable in the Deny statement; every Allow lists explicit actions.
  assert {
    condition = alltrue([
      for k in ["admins", "ops"] : alltrue([
        for s in data.aws_iam_policy_document.topic[k].statement :
        !anytrue([for a in s.actions : can(regex("\\*", a))])
        if s.effect == "Allow"
      ])
    ])
    error_message = "Allow statements of topic policies must list explicit actions, no wildcard."
  }
}

# EN45-AC3: CloudWatch and Budgets publish to ops only with SourceAccount and SourceArn conditions
run "en45_ac3_ops_services_scoped_by_source" {
  command = plan

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.topic["ops"].statement :
      anytrue([
        for c in s.condition :
        c.variable == "aws:SourceAccount" && c.test == "StringEquals" && toset(c.values) == toset(["123456789012"])
        ]) && anytrue([
        for c in s.condition :
        c.variable == "aws:SourceArn" && c.test == "ArnLike"
      ])
      if s.effect == "Allow"
    ])
    error_message = "Every Allow on the ops topic must carry aws:SourceAccount and aws:SourceArn conditions."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.topic["ops"].statement :
      s.effect == "Allow" && toset(s.actions) == toset(["sns:Publish"]) &&
      alltrue([for p in s.principals : p.type == "Service" && toset(p.identifiers) == toset(["cloudwatch.amazonaws.com"])]) &&
      anytrue([
        for c in s.condition :
        c.variable == "aws:SourceArn" && toset(c.values) == toset(["arn:aws:cloudwatch:us-east-1:123456789012:alarm:sc-dev-*"])
      ])
    ])
    error_message = "CloudWatch must be allowed to publish from the listed alarm ARNs only."
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.topic["ops"].statement :
      s.effect == "Allow" &&
      alltrue([for p in s.principals : p.type == "Service" && toset(p.identifiers) == toset(["budgets.amazonaws.com"])]) &&
      anytrue([
        for c in s.condition :
        c.variable == "aws:SourceArn" && toset(c.values) == toset(["arn:aws:budgets::123456789012:budget/sc-dev-*"])
      ])
    ])
    error_message = "Budgets must be allowed to publish from the listed budget ARNs only."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.topic["ops"].statement :
      alltrue([for p in s.principals : p.type != "AWS" || toset(p.identifiers) == toset(["*"])])
    ])
    error_message = "The ops topic must grant no IAM principal when none is listed."
  }
}

# EN45-AC3: SES may publish to ops only for the configuration set of this account
run "en45_ac3_ses_allowed_for_configuration_set_only" {
  command = plan

  variables {
    enable_configuration_set = true
  }

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.topic["ops"].statement :
      s.effect == "Allow" &&
      alltrue([for p in s.principals : p.type == "Service" && toset(p.identifiers) == toset(["ses.amazonaws.com"])]) &&
      anytrue([for c in s.condition : c.variable == "aws:SourceAccount" && toset(c.values) == toset(["123456789012"])]) &&
      anytrue([for c in s.condition : c.variable == "aws:SourceArn" && toset(c.values) == toset(["arn:aws:ses:us-east-1:123456789012:configuration-set/sc-dev-ses"])])
    ])
    error_message = "SES must be allowed to publish to ops with SourceAccount and the configuration set as SourceArn."
  }

  assert {
    condition = !anytrue([
      for s in data.aws_iam_policy_document.topic["admins"].statement :
      anytrue([for p in s.principals : contains(p.identifiers, "ses.amazonaws.com")])
    ])
    error_message = "SES must not be allowed to publish to the admins topic."
  }
}

# EN45-AC3: no service is allowed on a topic by default
run "en45_ac3_no_publisher_by_default" {
  command = plan

  variables {
    admins_publishers = {}
    ops_publishers    = {}
  }

  assert {
    condition = alltrue([
      for k in ["admins", "ops"] : length([
        for s in data.aws_iam_policy_document.topic[k].statement : s if s.effect == "Allow"
      ]) == 0
    ])
    error_message = "Without publishers, topic policies must contain no Allow statement."
  }
}

# EN45-AC3: rejects a service without any SourceArn pattern
run "en45_ac3_rejects_service_without_source_arn" {
  command = plan

  variables {
    ops_publishers = {
      services = { "cloudwatch.amazonaws.com" = [] }
    }
  }

  expect_failures = [var.ops_publishers]
}

# EN45-AC3: rejects a bare wildcard SourceArn
run "en45_ac3_rejects_wildcard_source_arn" {
  command = plan

  variables {
    ops_publishers = {
      services = { "cloudwatch.amazonaws.com" = ["*"] }
    }
  }

  expect_failures = [var.ops_publishers]
}

# EN45-AC3: rejects a service key that is not a service principal
run "en45_ac3_rejects_non_service_principal" {
  command = plan

  variables {
    ops_publishers = {
      services = { "123456789012" = ["arn:aws:cloudwatch:us-east-1:123456789012:alarm:sc-dev-*"] }
    }
  }

  expect_failures = [var.ops_publishers]
}

# EN45-AC3: rejects IAM principals that are not roles or that carry wildcards
run "en45_ac3_rejects_wildcard_publisher_role" {
  command = plan

  variables {
    ops_publishers = {
      principal_arns = ["arn:aws:iam::123456789012:role/*"]
    }
  }

  expect_failures = [var.ops_publishers]
}

# EN45-AC4: the admins topic accepts publishes from the listed roles only
run "en45_ac4_admins_publish_restricted_to_roles" {
  command = plan

  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.topic["admins"].statement :
      s.sid == "AllowPublishPrincipals" && s.effect == "Allow" && toset(s.actions) == toset(["sns:Publish"]) &&
      toset(s.resources) == toset([aws_sns_topic.this["admins"].arn]) &&
      alltrue([
        for p in s.principals :
        p.type == "AWS" && toset(p.identifiers) == toset(["arn:aws:iam::123456789012:role/sc-dev-tickets", "arn:aws:iam::123456789012:role/sc-dev-escalation"])
      ])
    ])
    error_message = "Only the tickets and escalation roles may publish to the admins topic."
  }
}

# EN45-AC4: the send policy allows ses:SendEmail on the sender identity with the FromAddress condition
run "en45_ac4_send_email_limited_to_sender_identity" {
  command = plan

  assert {
    condition     = length(data.aws_iam_policy_document.send_email.statement) == 1
    error_message = "The send policy must contain a single statement."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.send_email.statement :
      s.effect == "Allow" && toset(s.actions) == toset(["ses:SendEmail"]) &&
      toset(s.resources) == toset([aws_sesv2_email_identity.sender[0].arn])
    ])
    error_message = "The send policy must allow only ses:SendEmail on the sender identity."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.send_email.statement :
      anytrue([
        for c in s.condition :
        c.variable == "ses:FromAddress" && c.test == "StringLike" && toset(c.values) == toset(["noreply@example.com"])
      ])
    ])
    error_message = "The send policy must be conditioned on ses:FromAddress."
  }
}

# EN45-AC4: the send policy covers the domain identity and its From addresses when a domain is supplied
run "en45_ac4_send_email_includes_domain_identity" {
  command = plan

  variables {
    sender_domain = "mail.example.org"
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.send_email.statement :
      toset(s.resources) == toset([aws_sesv2_email_identity.sender[0].arn, aws_sesv2_email_identity.sender_domain[0].arn])
    ])
    error_message = "The send policy must cover the e-mail and the domain identities."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.send_email.statement :
      anytrue([
        for c in s.condition :
        c.variable == "ses:FromAddress" && toset(c.values) == toset(["noreply@example.com", "*@mail.example.org"])
      ])
    ])
    error_message = "The send policy must restrict ses:FromAddress to the sender address and the sender domain."
  }
}

# EN45-AC4: the configuration set is never a resource of ses:SendEmail; the identity default enforces it
run "en45_ac4_send_email_excludes_configuration_set" {
  command = plan

  variables {
    enable_configuration_set = true
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.send_email.statement :
      toset(s.resources) == toset([aws_sesv2_email_identity.sender[0].arn])
    ])
    error_message = "ses:SendEmail must be scoped to the sender identity ARN only, not to the configuration set."
  }

  assert {
    condition     = aws_sesv2_email_identity.sender[0].configuration_set_name == "sc-dev-ses"
    error_message = "The sender identity must default to the configuration set."
  }
}

# EN45-AC2: e-mail subscriptions are optional
run "en45_ac2_no_subscription_by_default" {
  command = plan

  assert {
    condition     = length(aws_sns_topic_subscription.email) == 0
    error_message = "No subscription must exist unless e-mail endpoints are provided."
  }
}

# EN45-AC2: e-mail subscriptions are created per topic from the variables
run "en45_ac2_email_subscriptions_per_topic" {
  command = plan

  variables {
    admins_email_endpoints = ["admin@example.com", "Admin@example.com"]
    ops_email_endpoints    = ["ops@example.com"]
  }

  assert {
    condition     = length(aws_sns_topic_subscription.email) == 2
    error_message = "Subscriptions must be deduplicated and created for each topic."
  }

  assert {
    condition     = alltrue([for s in values(aws_sns_topic_subscription.email) : s.protocol == "email"])
    error_message = "Subscriptions must use the email protocol."
  }

  assert {
    condition     = toset([for s in values(aws_sns_topic_subscription.email) : s.endpoint]) == toset(["admin@example.com", "ops@example.com"])
    error_message = "Subscription endpoints must come from the variables."
  }

  assert {
    condition     = alltrue([for k in keys(aws_sns_topic_subscription.email) : !can(regex("@", k))])
    error_message = "Resource keys must not contain e-mail addresses."
  }
}

# EN45-AC2: rejects an invalid subscription address
run "en45_ac2_rejects_invalid_subscription_address" {
  command = plan

  variables {
    ops_email_endpoints = ["not-an-address"]
  }

  expect_failures = [var.ops_email_endpoints]
}
