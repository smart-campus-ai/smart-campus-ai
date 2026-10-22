data "aws_iam_policy_document" "assume" {
  statement {
    sid     = "LambdaAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    # Confused deputy protection: only this function, in this account, can assume the role.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [local.function_arn]
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = local.role_name
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  permissions_boundary = var.permissions_boundary_arn

  tags = local.tags
}

# Equivalent of AWSLambdaBasicExecutionRole and AWSXRayDaemonWriteAccess, scoped to this function. The log group is
# created by this module, so logs:CreateLogGroup is not granted.
data "aws_iam_policy_document" "execution" {
  # checkov:skip=CKV_AWS_356: X-Ray trace submission and sampling APIs have no resource-level support, so "*" is the only valid resource for the XRay statement.
  source_policy_documents = var.extra_policy_json == null ? [] : [var.extra_policy_json]

  statement {
    sid       = "WriteLogs"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.this.arn}:*"]
  }

  statement {
    sid    = "XRay"
    effect = "Allow"
    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
      "xray:GetSamplingRules",
      "xray:GetSamplingTargets",
      "xray:GetSamplingStatisticsSummaries",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "DecryptEnvironment"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [var.environment_kms_key_arn]

    # Lambda sets this encryption context when it decrypts the environment: the key is usable for this function only.
    condition {
      test     = "StringEquals"
      variable = "kms:EncryptionContext:aws:lambda:FunctionArn"
      values   = [local.function_arn]
    }
  }

  dynamic "statement" {
    for_each = var.enable_dlq ? [1] : []

    content {
      sid       = "SendToDlq"
      effect    = "Allow"
      actions   = ["sqs:SendMessage"]
      resources = [aws_sqs_queue.dlq[0].arn]
    }
  }

  dynamic "statement" {
    for_each = var.enable_dlq ? [1] : []

    content {
      sid       = "UseDlqKey"
      effect    = "Allow"
      actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
      resources = [var.dlq_kms_key_arn]

      # The key is only usable through SQS, not directly.
      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["sqs.${local.region}.amazonaws.com"]
      }
    }
  }

  dynamic "statement" {
    for_each = var.on_failure_destination_arn == null ? [] : [var.on_failure_destination_arn]

    content {
      sid       = "SendToOnFailureDestination"
      effect    = "Allow"
      actions   = local.destination_actions[local.destination_service]
      resources = [statement.value]
    }
  }
}

resource "aws_iam_role_policy" "execution" {
  name   = "${local.name}-execution"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.execution.json
}
