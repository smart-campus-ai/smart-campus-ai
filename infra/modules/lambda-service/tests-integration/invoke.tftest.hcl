# Integration test (command = apply, real account), run on demand and never by `task test:unit`:
#
#   tofu -chdir=infra/modules/lambda-service init -backend=false
#   tofu -chdir=infra/modules/lambda-service test -test-directory=tests-integration
#
# Needs AWS credentials for the dev account and, through TF_VAR_*, the identifiers of existing resources:
#   TF_VAR_logs_kms_key_arn, TF_VAR_environment_kms_key_arn, TF_VAR_permissions_boundary_arn
# The resources are destroyed at the end of the test.
#
# Purpose: prove that Lambda can still assume the execution role with the aws:SourceArn condition of the trust policy
# (unqualified function ARN), also when the function is invoked through the live alias. If the role could not be
# assumed, the Invoke API call is rejected and the run fails. The placeholder code has no handler, so the function
# itself answers with a function error: that is expected and accepted, only the Invoke API status matters.

provider "aws" {
  region = "eu-west-3"
}

run "deploy" {
  command = apply

  variables {
    name_prefix           = "sc-dev"
    function_name         = "itest-invoke"
    runtime               = "python3.13"
    handler               = "app.handler"
    log_retention_in_days = 1
  }

  assert {
    condition     = output.alias_name == "live"
    error_message = "The live alias must be created."
  }
}

run "invoke_live_alias_assumes_the_role" {
  command = apply

  module {
    source = "./tests-integration/invoke"
  }

  variables {
    function_name = run.deploy.function_name
    qualifier     = run.deploy.alias_name
    region        = "eu-west-3"
  }

  assert {
    condition     = terraform_data.invoke.id != ""
    error_message = "The invocation of the live alias must succeed at the API level (the role is assumable)."
  }
}
