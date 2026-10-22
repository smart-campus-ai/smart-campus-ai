# The service-linked role cannot carry a permissions boundary and is managed by AWS. It can exist only once per
# account: set enable_config_service_linked_role to false when Config was already used in this account.
resource "aws_iam_service_linked_role" "config" {
  count = var.enable_config && var.enable_config_service_linked_role ? 1 : 0

  aws_service_name = "config.amazonaws.com"
}

resource "aws_config_configuration_recorder" "this" {
  count = var.enable_config ? 1 : 0

  name     = "${var.name_prefix}-config"
  role_arn = local.config_role_arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }

  depends_on = [aws_iam_service_linked_role.config]
}

resource "aws_config_delivery_channel" "this" {
  count = var.enable_config ? 1 : 0

  name           = "${var.name_prefix}-config"
  s3_bucket_name = aws_s3_bucket.logs[0].id
  s3_key_prefix  = local.config_log_prefix
  s3_kms_key_arn = var.kms_key_arn

  snapshot_delivery_properties {
    delivery_frequency = "TwentyFour_Hours"
  }

  depends_on = [
    aws_config_configuration_recorder.this,
    aws_s3_bucket_policy.logs,
  ]
}

resource "aws_config_configuration_recorder_status" "this" {
  count = var.enable_config ? 1 : 0

  name       = aws_config_configuration_recorder.this[0].name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.this]
}
