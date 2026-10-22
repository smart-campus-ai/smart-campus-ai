resource "aws_securityhub_account" "this" {
  count = var.enable_securityhub ? 1 : 0

  # Standards are subscribed explicitly below; the default set would also enable CIS and others at their latest version.
  enable_default_standards  = false
  auto_enable_controls      = true
  control_finding_generator = "SECURITY_CONTROL"
}

resource "aws_securityhub_standards_subscription" "fsbp" {
  count = var.enable_securityhub ? 1 : 0

  standards_arn = local.fsbp_standards_arn

  depends_on = [aws_securityhub_account.this]
}
