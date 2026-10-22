# Integration skeleton (EN-13-AC3, finding F9). On demand only, needs AWS credentials of the dev account:
#   task test:integration ENV=dev
# The directory is tests-integration/ (not tests/) because `task test:unit` runs every file of tests/ and must stay
# offline; the Taskfile runs this one with -test-directory=tests-integration.
#
# Required inputs (TF_VAR_*): existing_oidc_provider_arn (an account holds one GitHub provider per URL, so this test
# never creates one), state_bucket_arn and state_kms_key_arn of the dev state backend.
#
# Known limits of this skeleton:
#   - the two boundaries have prevent_destroy = true, so the cleanup of `tofu test` stops on them: use a throwaway
#     name_prefix (below) and delete the leftovers by hand, or run it in a sandbox account;
#   - the real proof of AC3, "CreateRole without the workload boundary is denied", needs a session that ASSUMES the apply
#     role. The second run below documents the scenario; complete it with a helper configuration that creates an
#     aws_iam_role without permissions_boundary through a provider alias with assume_role = apply_role_arns["dev"], and
#     assert on the AccessDenied diagnostic.

variables {
  name_prefix          = "scit"
  github_repository    = "smart-campus-ai/smart-campus-ai"
  allowed_regions      = ["eu-west-3", "us-east-1"]
  create_oidc_provider = false
}

# The roles and the per-environment boundaries exist with the expected names once applied
run "en13_ac3_integration_roles_and_boundaries_exist" {
  command = apply

  assert {
    condition     = toset(keys(output.apply_role_arns)) == toset(["dev", "prod"])
    error_message = "One apply role per environment must exist."
  }

  assert {
    condition     = toset(keys(output.workload_boundary_arns)) == toset(["dev", "prod"])
    error_message = "One workload boundary per environment must exist."
  }

  assert {
    condition     = alltrue([for e, arn in output.workload_boundary_arns : endswith(arn, ":policy/scit-${e}-workload-boundary")])
    error_message = "Each workload boundary must be named <prefix>-<env>-workload-boundary."
  }
}

# TODO (QE): as the dev apply role, iam:CreateRole on scit-dev-probe WITHOUT a permissions boundary must fail with
# AccessDenied, and with the scit-prod-workload-boundary must fail too; with scit-dev-workload-boundary it must succeed.
