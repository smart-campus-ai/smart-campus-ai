# The infrastructure owns the configuration of the function, the application pipeline (EN-74) owns its code. The first
# apply deploys this placeholder archive; the pipeline replaces it and OpenTofu ignores the code attributes afterwards.
data "archive_file" "placeholder" {
  type        = "zip"
  output_path = "${path.module}/.build/${local.name}.zip"

  source {
    content  = "Placeholder deployed by OpenTofu. The application pipeline replaces this code.\n"
    filename = "placeholder.txt"
  }
}

resource "aws_lambda_function" "this" {
  # checkov:skip=CKV_AWS_117: No VPC by design (ADR): every dependency is a regional AWS API reached over TLS with IAM auth.
  # checkov:skip=CKV_AWS_272: Code signing is out of scope for the workshop; the pipeline deploys from the protected main branches only.
  function_name = local.name
  description   = var.description
  role          = aws_iam_role.this.arn

  runtime       = var.runtime
  handler       = var.handler
  architectures = ["arm64"]
  memory_size   = var.memory_size
  timeout       = var.timeout

  reserved_concurrent_executions = var.reserved_concurrent_executions

  # A version is published on every configuration change; the pipeline decides when the live alias moves to it.
  publish = true

  filename         = data.archive_file.placeholder.output_path
  source_code_hash = data.archive_file.placeholder.output_base64sha256

  kms_key_arn = var.environment_kms_key_arn

  tracing_config {
    mode = "Active"
  }

  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.this.name
  }

  dynamic "environment" {
    for_each = length(var.environment_variables) > 0 ? [var.environment_variables] : []

    content {
      variables = environment.value
    }
  }

  dynamic "dead_letter_config" {
    for_each = var.enable_dlq ? [1] : []

    content {
      target_arn = aws_sqs_queue.dlq[0].arn
    }
  }

  tags = local.tags

  # The log group and the role policy must exist before the first invocation.
  depends_on = [aws_cloudwatch_log_group.this, aws_iam_role_policy.execution]

  lifecycle {
    ignore_changes = [filename, source_code_hash, s3_key, s3_object_version]
  }
}

# Integrations (API Gateway, event source mappings, Scheduler) target this alias, never $LATEST.
resource "aws_lambda_alias" "live" {
  name             = local.alias_name
  description      = "Version served to the integrations."
  function_name    = aws_lambda_function.this.function_name
  function_version = aws_lambda_function.this.version

  # The first apply points the alias at the first published version. Afterwards the application pipeline (EN-74) owns
  # the promotion and the rollbacks: a later apply must not move the alias.
  lifecycle {
    ignore_changes = [function_version]
  }
}

resource "aws_lambda_function_event_invoke_config" "live" {
  count = var.on_failure_destination_arn == null ? 0 : 1

  function_name = aws_lambda_function.this.function_name
  qualifier     = aws_lambda_alias.live.name

  destination_config {
    on_failure {
      destination = var.on_failure_destination_arn
    }
  }
}
