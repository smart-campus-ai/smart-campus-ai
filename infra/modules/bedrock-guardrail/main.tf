resource "aws_bedrock_guardrail" "this" {
  name                      = local.name
  description               = "Guardrail of the ${var.name_prefix} campus assistant: denied topics, PII masking, prompt-attack filter and contextual grounding."
  kms_key_arn               = var.kms_key_arn
  blocked_input_messaging   = var.blocked_input_message
  blocked_outputs_messaging = var.blocked_output_message

  tags = local.tags

  lifecycle {
    precondition {
      condition     = length(local.pii_overlap) == 0
      error_message = "A PII type cannot be in both pii_entities_anonymize and pii_entities_block."
    }

    precondition {
      condition     = length(local.pii_missing) == 0
      error_message = "EMAIL, PHONE and NAME must be covered by pii_entities_anonymize or pii_entities_block (EN-52-AC2)."
    }
  }

  topic_policy_config {
    dynamic "topics_config" {
      for_each = var.denied_topics

      content {
        name       = topics_config.key
        definition = topics_config.value.definition
        examples   = topics_config.value.examples
        type       = "DENY"
      }
    }
  }

  content_policy_config {
    dynamic "filters_config" {
      for_each = local.content_filters

      content {
        type            = filters_config.key
        input_strength  = filters_config.value.input_strength
        output_strength = filters_config.value.output_strength
      }
    }
  }

  sensitive_information_policy_config {
    dynamic "pii_entities_config" {
      for_each = local.pii_entities

      content {
        type           = pii_entities_config.key
        action         = pii_entities_config.value
        input_action   = pii_entities_config.value
        output_action  = pii_entities_config.value
        input_enabled  = true
        output_enabled = true
      }
    }
  }

  word_policy_config {
    managed_word_lists_config {
      type = "PROFANITY"
    }
  }

  contextual_grounding_policy_config {
    dynamic "filters_config" {
      for_each = local.contextual_grounding_filters

      content {
        type      = filters_config.key
        threshold = filters_config.value
      }
    }
  }
}

# A version is an immutable snapshot of the guardrail. Replacing it whenever the guardrail changes
# publishes a new version on every apply that modifies the configuration (EN-52-AC6); the "chat"
# function receives guardrail_version, so it never runs against the mutable DRAFT.
# create_before_destroy: the new version exists before the previous one is deleted.
resource "aws_bedrock_guardrail_version" "this" {
  guardrail_arn = aws_bedrock_guardrail.this.guardrail_arn
  description   = "Published by OpenTofu for ${local.name}."

  lifecycle {
    create_before_destroy = true
    replace_triggered_by  = [aws_bedrock_guardrail.this]
  }
}
