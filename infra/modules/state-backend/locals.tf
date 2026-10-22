data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  account_id       = data.aws_caller_identity.current.account_id
  account_root_arn = "arn:${data.aws_partition.current.partition}:iam::${local.account_id}:root"

  # S3 bucket names are global: the account ID keeps the name unique without any hardcoded value.
  bucket_name = "${var.name_prefix}-tfstate-${local.account_id}"
  kms_alias   = "alias/${var.name_prefix}-tfstate"

  access_log_prefix = "s3/${local.bucket_name}/"
}
