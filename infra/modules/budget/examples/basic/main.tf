# Basic usage: monthly budget of 50 USD with email notifications.
# The SNS topic ARN is null: notifications go only to the email addresses.
#
# Workshop limitation: the workshop IAM role is denied budgets:* (including budgets:DescribeBudgets),
# so this module cannot be applied in the workshop account. The CI apply will fail with an Access Denied.
# Set enable_budget = false in the stack variables to skip the module during the workshop.

module "budget" {
  source = "../.."

  name_prefix              = "sc-dev"
  monthly_limit_usd        = 50
  notification_emails      = ["ops@example.com"]
  enable_anomaly_detection = false
}
