# Monthly budget. The workshop IAM role is denied budgets:*, so enable_budget is false in the dev and prod tfvars of the
# workshop account; enable it only in an account that allows AWS Budgets. The module publishes its alerts to the ops
# alerts topic, whose policy merges the module's publish statement (alerts.tf).
module "budget" {
  count = var.enable_budget ? 1 : 0

  source = "../../modules/budget"

  name_prefix              = var.name_prefix
  monthly_limit_usd        = var.budget_monthly_limit_usd
  sns_topic_arn            = aws_sns_topic.alerts.arn
  notification_emails      = var.budget_notification_emails
  enable_anomaly_detection = var.budget_enable_anomaly_detection
}
