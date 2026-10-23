# Policy for the "tickets" role, which signs the presigned POST (upload) and the presigned GET (download). The role
# itself belongs to another module; this module only publishes the document, scoped to the attachments prefix.
data "aws_iam_policy_document" "tickets_rw" {
  statement {
    sid       = "ReadWriteAttachments"
    effect    = "Allow"
    resources = ["${local.bucket_arn}/${var.attachments_prefix}*"]
    actions   = ["s3:GetObject", "s3:PutObject"]
  }
}
