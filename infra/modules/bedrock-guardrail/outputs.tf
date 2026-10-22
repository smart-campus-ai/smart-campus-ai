output "guardrail_id" {
  description = "ID of the guardrail. Pair it with guardrail_version in the Bedrock calls (guardrailIdentifier)."
  value       = aws_bedrock_guardrail.this.guardrail_id
}

output "guardrail_arn" {
  description = "ARN of the guardrail, scoped in the bedrock:ApplyGuardrail / bedrock:InvokeModel permissions of the chat function."
  value       = aws_bedrock_guardrail.this.guardrail_arn
}

output "guardrail_version" {
  description = "Published (immutable) version of the guardrail, passed to the chat function as guardrailVersion."
  value       = aws_bedrock_guardrail_version.this.version
}
