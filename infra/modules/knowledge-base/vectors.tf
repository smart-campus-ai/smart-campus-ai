resource "aws_s3vectors_vector_bucket" "this" {
  vector_bucket_name = local.vector_bucket_name
  force_destroy      = false

  encryption_configuration {
    sse_type    = "aws:kms"
    kms_key_arn = var.kms_key_arn
  }

  tags = merge(var.tags, { Name = local.vector_bucket_name })
}

resource "aws_s3vectors_index" "this" {
  index_name         = local.vector_index_name
  vector_bucket_name = aws_s3vectors_vector_bucket.this.vector_bucket_name

  data_type       = "float32"
  dimension       = var.vector_dimension
  distance_metric = var.distance_metric

  encryption_configuration {
    sse_type    = "aws:kms"
    kms_key_arn = var.kms_key_arn
  }

  metadata_configuration {
    non_filterable_metadata_keys = local.non_filterable_metadata_keys
  }

  tags = merge(var.tags, { Name = local.vector_index_name })
}
