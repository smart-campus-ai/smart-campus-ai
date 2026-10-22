mock_provider "aws" {
  # Computed attributes are unknown at plan time; the version and the outputs consume them.
  override_resource {
    target = aws_bedrock_guardrail.this
    values = {
      guardrail_id  = "abcd1234efgh"
      guardrail_arn = "arn:aws:bedrock:eu-west-3:123456789012:guardrail/abcd1234efgh"
    }
  }

  override_resource {
    target = aws_bedrock_guardrail_version.this
    values = {
      version = "3"
    }
  }
}

variables {
  name_prefix = "sc-dev"
  environment = "dev"

  # Documentation account ID and placeholder key ID.
  kms_key_arn = "arn:aws:kms:eu-west-3:123456789012:key/00000000-0000-0000-0000-000000000000"

  denied_topics = {
    "Legal advice" = {
      definition = "Legal opinions or recommendations about disputes, contracts or liability."
      examples   = ["Puis-je attaquer l'école en justice ?"]
    }
    "Medical advice" = {
      definition = "Diagnoses or treatment recommendations for health problems."
      examples   = ["Quel médicament dois-je prendre contre la migraine ?", "Est-ce grave si j'ai de la fièvre ?"]
    }
    "Exam answers" = {
      definition = "Requests to produce answers to graded exams or assignments."
    }
  }
}

# EN-52-AC1: every denied topic of the variable is declared in the guardrail
run "en52_ac1_denied_topics" {
  command = plan

  assert {
    condition     = toset([for t in aws_bedrock_guardrail.this.topic_policy_config[0].topics_config : t.name]) == toset(["Legal advice", "Medical advice", "Exam answers"])
    error_message = "Every topic of denied_topics must be declared in the guardrail."
  }

  assert {
    condition     = alltrue([for t in aws_bedrock_guardrail.this.topic_policy_config[0].topics_config : t.type == "DENY"])
    error_message = "Every topic must be of type DENY."
  }

  assert {
    condition     = { for t in aws_bedrock_guardrail.this.topic_policy_config[0].topics_config : t.name => length(t.examples) }["Medical advice"] == 2
    error_message = "The examples of a topic must be passed to the guardrail."
  }
}

run "en52_ac1_denied_topics_required" {
  command = plan

  variables {
    denied_topics = {}
  }

  expect_failures = [var.denied_topics]
}

run "en52_ac1_denied_topics_too_many_examples" {
  command = plan

  variables {
    denied_topics = {
      "Legal advice" = {
        definition = "Legal opinions."
        examples   = ["a", "b", "c", "d", "e", "f"]
      }
    }
  }

  expect_failures = [var.denied_topics]
}

run "en52_ac1_denied_topics_definition_too_long" {
  command = plan

  variables {
    denied_topics = {
      "Legal advice" = {
        definition = join("", [for i in range(201) : "x"])
      }
    }
  }

  expect_failures = [var.denied_topics]
}

run "en52_ac1_denied_topics_invalid_name" {
  command = plan

  variables {
    denied_topics = {
      "Legal/advice" = {
        definition = "Legal opinions."
      }
    }
  }

  expect_failures = [var.denied_topics]
}

# EN-52-AC2: PII masked on input and output (email, phone, name at minimum); cards and passwords blocked
run "en52_ac2_pii_masking" {
  command = plan

  assert {
    condition     = length(aws_bedrock_guardrail.this.sensitive_information_policy_config) == 1
    error_message = "The sensitive information policy must be configured."
  }

  assert {
    condition = alltrue([
      for t in ["EMAIL", "PHONE", "NAME", "ADDRESS"] :
      { for p in aws_bedrock_guardrail.this.sensitive_information_policy_config[0].pii_entities_config : p.type => p.action }[t] == "ANONYMIZE"
    ])
    error_message = "EMAIL, PHONE, NAME and ADDRESS must be anonymized."
  }

  assert {
    condition = alltrue([
      for t in ["CREDIT_DEBIT_CARD_NUMBER", "PASSWORD"] :
      { for p in aws_bedrock_guardrail.this.sensitive_information_policy_config[0].pii_entities_config : p.type => p.action }[t] == "BLOCK"
    ])
    error_message = "Credit card numbers and passwords must be blocked."
  }

  assert {
    condition = alltrue([
      for p in aws_bedrock_guardrail.this.sensitive_information_policy_config[0].pii_entities_config :
      p.input_enabled && p.output_enabled && p.input_action == p.action && p.output_action == p.action
    ])
    error_message = "Every PII type must be handled on both input and output with the same action."
  }
}

run "en52_ac2_pii_minimum_covered" {
  command = plan

  variables {
    pii_entities_anonymize = ["EMAIL", "PHONE"]
  }

  expect_failures = [aws_bedrock_guardrail.this]
}

run "en52_ac2_pii_minimum_covered_by_block" {
  command = plan

  variables {
    pii_entities_anonymize = ["EMAIL", "PHONE"]
    pii_entities_block     = ["NAME", "PASSWORD"]
  }

  assert {
    condition     = { for p in aws_bedrock_guardrail.this.sensitive_information_policy_config[0].pii_entities_config : p.type => p.action }["NAME"] == "BLOCK"
    error_message = "A minimum type moved to pii_entities_block must be blocked."
  }
}

run "en52_ac2_pii_overlap_rejected" {
  command = plan

  variables {
    pii_entities_block = ["NAME", "PASSWORD"]
  }

  expect_failures = [aws_bedrock_guardrail.this]
}

run "en52_ac2_pii_unknown_type_anonymize" {
  command = plan

  variables {
    pii_entities_anonymize = ["EMAIL", "PHONE", "NAME", "SHOE_SIZE"]
  }

  expect_failures = [var.pii_entities_anonymize]
}

run "en52_ac2_pii_unknown_type_block" {
  command = plan

  variables {
    pii_entities_block = ["PASSWORD", "SHOE_SIZE"]
  }

  expect_failures = [var.pii_entities_block]
}

# EN-52-AC3: prompt attack filter enabled on inputs, plus the other content filters
run "en52_ac3_prompt_attack" {
  command = plan

  assert {
    condition     = { for f in aws_bedrock_guardrail.this.content_policy_config[0].filters_config : f.type => f.input_strength }["PROMPT_ATTACK"] == "HIGH"
    error_message = "The PROMPT_ATTACK filter must be HIGH on inputs."
  }

  assert {
    condition     = { for f in aws_bedrock_guardrail.this.content_policy_config[0].filters_config : f.type => f.output_strength }["PROMPT_ATTACK"] == "NONE"
    error_message = "The PROMPT_ATTACK filter has no output side: its output strength must be NONE."
  }
}

run "en52_ac3_content_filters" {
  command = plan

  assert {
    condition     = toset([for f in aws_bedrock_guardrail.this.content_policy_config[0].filters_config : f.type]) == toset(["HATE", "INSULTS", "SEXUAL", "VIOLENCE", "MISCONDUCT", "PROMPT_ATTACK"])
    error_message = "HATE, INSULTS, SEXUAL, VIOLENCE, MISCONDUCT and PROMPT_ATTACK filters must be configured."
  }

  assert {
    condition = alltrue([
      for f in aws_bedrock_guardrail.this.content_policy_config[0].filters_config :
      f.input_strength == "HIGH" if f.type != "PROMPT_ATTACK"
    ])
    error_message = "Content filters must default to HIGH on inputs."
  }

  assert {
    condition = alltrue([
      for f in aws_bedrock_guardrail.this.content_policy_config[0].filters_config :
      f.output_strength == "HIGH" if f.type != "PROMPT_ATTACK"
    ])
    error_message = "Content filters must default to HIGH on outputs."
  }
}

run "en52_ac3_content_filter_strength_variable" {
  command = plan

  variables {
    content_filter_strength = "MEDIUM"
  }

  assert {
    condition     = { for f in aws_bedrock_guardrail.this.content_policy_config[0].filters_config : f.type => f.input_strength }["HATE"] == "MEDIUM"
    error_message = "content_filter_strength must drive the content filters."
  }

  assert {
    condition     = { for f in aws_bedrock_guardrail.this.content_policy_config[0].filters_config : f.type => f.input_strength }["PROMPT_ATTACK"] == "HIGH"
    error_message = "content_filter_strength must never weaken the PROMPT_ATTACK filter."
  }
}

run "en52_ac3_content_filter_strength_invalid" {
  command = plan

  variables {
    content_filter_strength = "NONE"
  }

  expect_failures = [var.content_filter_strength]
}

run "en52_ac3_managed_profanity_list" {
  command = plan

  assert {
    condition     = [for m in aws_bedrock_guardrail.this.word_policy_config[0].managed_word_lists_config : m.type] == ["PROFANITY"]
    error_message = "The managed PROFANITY word list must be enabled."
  }
}

# EN-52-AC4: contextual grounding and relevance enabled with the threshold variables
run "en52_ac4_contextual_grounding" {
  command = plan

  variables {
    grounding_threshold = 0.8
    relevance_threshold = 0.6
  }

  assert {
    condition     = length(aws_bedrock_guardrail.this.contextual_grounding_policy_config) == 1
    error_message = "The contextual grounding policy must be configured."
  }

  assert {
    condition     = { for f in aws_bedrock_guardrail.this.contextual_grounding_policy_config[0].filters_config : f.type => f.threshold }["GROUNDING"] == 0.8
    error_message = "The GROUNDING filter must use grounding_threshold."
  }

  assert {
    condition     = { for f in aws_bedrock_guardrail.this.contextual_grounding_policy_config[0].filters_config : f.type => f.threshold }["RELEVANCE"] == 0.6
    error_message = "The RELEVANCE filter must use relevance_threshold."
  }
}

run "en52_ac4_default_thresholds" {
  command = plan

  assert {
    condition     = toset([for f in aws_bedrock_guardrail.this.contextual_grounding_policy_config[0].filters_config : f.type]) == toset(["GROUNDING", "RELEVANCE"])
    error_message = "Grounding and relevance must be enabled with the default thresholds."
  }
}

run "en52_ac4_grounding_threshold_above_range" {
  command = plan

  variables {
    grounding_threshold = 1.5
  }

  expect_failures = [var.grounding_threshold]
}

run "en52_ac4_grounding_threshold_below_range" {
  command = plan

  variables {
    grounding_threshold = -0.1
  }

  expect_failures = [var.grounding_threshold]
}

run "en52_ac4_relevance_threshold_above_range" {
  command = plan

  variables {
    relevance_threshold = 1.5
  }

  expect_failures = [var.relevance_threshold]
}

run "en52_ac4_relevance_threshold_below_range" {
  command = plan

  variables {
    relevance_threshold = -0.1
  }

  expect_failures = [var.relevance_threshold]
}

# EN-52-AC5: blocked messages are "je ne sais pas" with the offer to create a ticket
run "en52_ac5_blocked_messages" {
  command = plan

  assert {
    condition = (
      strcontains(lower(aws_bedrock_guardrail.this.blocked_outputs_messaging), "je ne sais pas") &&
      strcontains(lower(aws_bedrock_guardrail.this.blocked_outputs_messaging), "ticket")
    )
    error_message = "The blocked answer message must say \"je ne sais pas\" and offer to create a ticket."
  }

  assert {
    condition = (
      strcontains(lower(aws_bedrock_guardrail.this.blocked_input_messaging), "je ne sais pas") &&
      strcontains(lower(aws_bedrock_guardrail.this.blocked_input_messaging), "ticket")
    )
    error_message = "The blocked prompt message must say \"je ne sais pas\" and offer to create a ticket."
  }
}

run "en52_ac5_blocked_message_too_long" {
  command = plan

  variables {
    blocked_output_message = join("", [for i in range(501) : "x"])
  }

  expect_failures = [var.blocked_output_message]
}

run "en52_ac5_blocked_input_message_empty" {
  command = plan

  variables {
    blocked_input_message = ""
  }

  expect_failures = [var.blocked_input_message]
}

# EN-52-AC6: a version is published and exposed with the guardrail id and ARN
run "en52_ac6_published_version" {
  command = plan

  assert {
    condition     = aws_bedrock_guardrail_version.this.guardrail_arn == "arn:aws:bedrock:eu-west-3:123456789012:guardrail/abcd1234efgh"
    error_message = "The version must be published for the guardrail."
  }

  assert {
    condition     = output.guardrail_version == "3"
    error_message = "The guardrail_version output must expose the published version, not DRAFT."
  }

  assert {
    condition     = output.guardrail_id == "abcd1234efgh"
    error_message = "The guardrail_id output must expose the guardrail ID."
  }

  assert {
    condition     = output.guardrail_arn == "arn:aws:bedrock:eu-west-3:123456789012:guardrail/abcd1234efgh"
    error_message = "The guardrail_arn output must expose the guardrail ARN."
  }
}

# Non-functional: encryption with the ai key, naming, tags
run "en52_nfr_kms_encryption" {
  command = plan

  assert {
    condition     = aws_bedrock_guardrail.this.kms_key_arn == var.kms_key_arn
    error_message = "The guardrail must be encrypted with the key given in kms_key_arn."
  }
}

run "en52_nfr_name_and_tags" {
  command = plan

  variables {
    tags = {
      Owner = "ops"
    }
  }

  assert {
    condition     = aws_bedrock_guardrail.this.name == "sc-dev-guardrail"
    error_message = "The guardrail name must be <name_prefix>-guardrail."
  }

  assert {
    condition     = aws_bedrock_guardrail.this.tags["Environment"] == "dev" && aws_bedrock_guardrail.this.tags["Owner"] == "ops"
    error_message = "Tags must include Environment and the extra tags."
  }
}

run "en52_nfr_environment_tag_not_overridable" {
  command = plan

  variables {
    tags = {
      Environment = "prod"
    }
  }

  assert {
    condition     = aws_bedrock_guardrail.this.tags["Environment"] == "dev"
    error_message = "The Environment tag must come from var.environment."
  }
}

run "en52_nfr_kms_key_alias_rejected" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:eu-west-3:123456789012:alias/sc-dev-ai"
  }

  expect_failures = [var.kms_key_arn]
}

run "en52_nfr_name_prefix_invalid" {
  command = plan

  variables {
    name_prefix = "SC_DEV"
  }

  expect_failures = [var.name_prefix]
}

run "en52_nfr_environment_invalid" {
  command = plan

  variables {
    environment = "Dev"
  }

  expect_failures = [var.environment]
}
