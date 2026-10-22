# Integration test: observability module against the dev account (EN-61).
#
# Prerequisites:
# - The platform stack must be applied in the dev environment.
# - SSM parameters under /smartcampus/dev/platform/ must exist.
# - The caller must have AWS credentials for the dev account.
#
# Run: tofu -chdir=infra/modules/observability test -filter=tests/integration.tftest.hcl
#
# This skeleton is on-demand. Add assertions as needed:
# - EN61-AC1: assert Lambda/API/WAF log groups exist with KMS encryption and retention
# - EN61-AC2: assert API tracing and Lambda active tracing are enabled
# - EN61-AC5: trigger a CloudFront WAF block and assert the alarm fires
# - EN61-AC6: assert API access log format omits Authorization and bodies

provider "aws" {
  region = "us-east-1"
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

data "aws_ssm_parameter" "alarm_topic_arn" {
  name = "/smartcampus/dev/notifications/ops-topic-arn"
}

# Example: verify the dashboard exists (EN61-AC3)
run "en61_integration_dashboard_exists" {
  command = apply

  module {
    source = "./tests/fixtures/observability_dev"
  }

  assert {
    condition     = module.observability.dashboard_name == "sc-dev-overview"
    error_message = "The dashboard must exist and be named sc-dev-overview."
  }
}
