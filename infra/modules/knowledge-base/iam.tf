data "aws_iam_policy_document" "service_trust" {
  statement {
    sid     = "BedrockKnowledgeBaseAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [local.knowledge_base_arn_pattern]
    }
  }
}

resource "aws_iam_role" "service" {
  name                 = local.service_role_name
  description          = "Service role of the ${local.name} Bedrock knowledge base"
  assume_role_policy   = data.aws_iam_policy_document.service_trust.json
  permissions_boundary = var.permissions_boundary_arn

  tags = merge(var.tags, { Name = local.service_role_name })
}

data "aws_iam_policy_document" "service" {
  statement {
    sid       = "ListSourceBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.sources.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceAccount"
      values   = [local.account_id]
    }

    # Listing is limited to the source prefix: the role must not see the other keys of the bucket.
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${var.source_prefix}*"]
    }
  }

  statement {
    sid       = "ReadSourceDocuments"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.sources.arn}/${var.source_prefix}*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid    = "UseVectorIndex"
    effect = "Allow"
    actions = [
      "s3vectors:DeleteVectors",
      "s3vectors:GetIndex",
      "s3vectors:GetVectors",
      "s3vectors:PutVectors",
      "s3vectors:QueryVectors",
    ]
    resources = [aws_s3vectors_index.this.index_arn]
  }

  statement {
    sid       = "InvokeEmbeddingModel"
    effect    = "Allow"
    actions   = ["bedrock:InvokeModel"]
    resources = local.embedding_model_invoke_arns
  }

  statement {
    sid    = "UseAiKey"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:GenerateDataKey",
    ]
    resources = [var.kms_key_arn]

    # The key is only usable through S3 and Bedrock in this region, never directly by the role.
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values = [
        "s3.${local.region}.amazonaws.com",
        "bedrock.${local.region}.amazonaws.com",
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role_policy" "service" {
  name   = "${local.service_role_name}-access"
  role   = aws_iam_role.service.id
  policy = data.aws_iam_policy_document.service.json
}
