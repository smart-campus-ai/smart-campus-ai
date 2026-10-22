locals {
  name = "${var.name_prefix}-guardrail"

  tags = merge(var.tags, { Environment = var.environment })

  # Content filters applied on both prompts and answers. PROMPT_ATTACK only exists on inputs:
  # Bedrock requires its output strength to be NONE.
  content_filters = merge(
    {
      for type in ["HATE", "INSULTS", "SEXUAL", "VIOLENCE", "MISCONDUCT"] : type => {
        input_strength  = var.content_filter_strength
        output_strength = var.content_filter_strength
      }
    },
    {
      PROMPT_ATTACK = {
        input_strength  = "HIGH"
        output_strength = "NONE"
      }
    },
  )

  # Cross-variable PII rules, enforced by preconditions on the guardrail (variable validations that
  # reference each other form a cycle).
  pii_overlap = setintersection(var.pii_entities_anonymize, var.pii_entities_block)
  pii_missing = setsubtract(toset(["EMAIL", "PHONE", "NAME"]), setunion(var.pii_entities_anonymize, var.pii_entities_block))

  # PII type => action. The preconditions on the guardrail guarantee the two sets do not overlap.
  pii_entities = merge(
    { for type in var.pii_entities_anonymize : type => "ANONYMIZE" },
    { for type in var.pii_entities_block : type => "BLOCK" },
  )

  contextual_grounding_filters = {
    GROUNDING = var.grounding_threshold
    RELEVANCE = var.relevance_threshold
  }
}
