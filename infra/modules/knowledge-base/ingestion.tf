# Document changes trigger the kb-sync function (EN-51 AC4), which starts an ingestion job. The function itself is owned
# by the platform stack; the module only wires the bucket to it.
resource "aws_lambda_permission" "ingestion" {
  count = var.enable_ingestion_notification ? 1 : 0

  statement_id  = "AllowSourceBucketInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.ingestion_function_arn
  principal     = "s3.amazonaws.com"

  # Confused deputy: only this bucket, in this account, can invoke the function.
  source_arn     = aws_s3_bucket.sources.arn
  source_account = local.account_id
}

resource "aws_s3_bucket_notification" "sources" {
  count = var.enable_ingestion_notification ? 1 : 0

  bucket = aws_s3_bucket.sources.id

  lambda_function {
    lambda_function_arn = var.ingestion_function_arn
    events              = ["s3:ObjectCreated:*", "s3:ObjectRemoved:*"]
    filter_prefix       = var.source_prefix
  }

  # S3 validates the invoke permission when it saves the notification configuration.
  depends_on = [aws_lambda_permission.ingestion]
}
