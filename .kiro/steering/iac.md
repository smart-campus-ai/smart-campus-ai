---
inclusion: fileMatch
fileMatchPattern: "infra/**"
---

# OpenTofu conventions

## Versions
- OpenTofu latest stable 1.x (≥ 1.10), pinned in `.mise.toml`; `required_version` uses `~>` on the minor. AWS provider pinned with `~>` on the major; `.terraform.lock.hcl` committed with hashes for linux_amd64, linux_arm64, darwin_arm64, windows_amd64.
- Never use `terraform`; the binary is `tofu`.

## Module layout (`infra/modules/<name>/`)
```
versions.tf      # required_providers only (+ configuration_aliases, e.g. aws.us_east_1)
variables.tf     # typed, described, validated; no env-specific defaults
main.tf          # or split by resource family: iam.tf, kms.tf, logs.tf ...
locals.tf
outputs.tf       # described; never output secrets (sensitive = true if unavoidable)
README.md        # terraform-docs between <!-- BEGIN_TF_DOCS --> markers
tests/unit.tftest.hcl         # mock_provider + command = plan, assertions on invariants
tests/integration.tftest.hcl  # command = apply, real account, run on demand
examples/basic/
```
- **No provider or backend block in modules.** Modules receive everything via variables; they never look up other modules' resources with data sources (only `aws_caller_identity`, `aws_partition`, `aws_region` and policy documents).
- Feature flags are booleans named `enable_<feature>`; optional blocks via `dynamic`/`count` on the flag.
- Prefer `for_each` over `count` for collections; keys must be stable strings.
- Names: `local.name = "${var.name_prefix}-<component>"`; `name_prefix` = `sc-<env>`. No hardcoded account IDs, regions or ARNs.
- Tags: provider `default_tags` in stacks (`Project, Environment, Owner, ManagedBy=opentofu, Repository, DataClassification`); modules accept extra `tags`.

## Stacks and environments
- `stacks/foundation` → `stacks/platform`. Each stack = one state (`<env>/<stack>.tfstate`). Contract between stacks = SSM parameters under `/smartcampus/<env>/<stack>/<key>` published by the producer (no `terraform_remote_state`).
- `envs/<env>/backend.hcl` + `envs/<env>/<stack>.tfvars`. Init: `tofu -chdir=infra/stacks/<stack> init -backend-config=../../envs/<env>/backend.hcl`.
- Backend: S3 with `use_lockfile = true`, `encrypt = true`, `kms_key_id`; plus the OpenTofu `encryption` block (`key_provider "aws_kms"`, `method "aes_gcm"`, state and plan `enforced = true`).
- Providers in stacks: default region `eu-west-3`; alias `aws.us_east_1` for CloudFront-scoped WAF and ACM.

## Resource rules
- IAM: `aws_iam_policy_document` only, scoped ARNs, conditions; permissions boundary on every role.
- Lambda module (`lambda-service`): arm64, runtime/handler variables, `tracing_config { mode = "Active" }`, explicit `aws_cloudwatch_log_group` (KMS, retention), alias `live`, optional DLQ/destinations, reserved concurrency variable, placeholder artifact + `lifecycle { ignore_changes = [filename, source_code_hash, s3_key, s3_object_version] }`.
- Logs: retention variable (dev 14 days, prod 90 days), KMS-encrypted.
- Use OpenTofu `check` blocks for post-apply assertions where useful (e.g. distribution status, HTTPS redirect).

## Quality gates (all in `task check`)
`tofu fmt -check -recursive`, `tofu validate` per stack/module, `tflint --recursive` (aws + terraform rulesets), `checkov -d infra --framework terraform` (+ custom policies in `policies/`), `trivy config infra`, `tofu test` (unit), terraform-docs check.

## Unit test expectations (per module)
Assert the security invariants the module is responsible for (e.g. bucket BPA all true, KMS rotation enabled, Lambda architecture arm64, log retention set, no wildcard action in generated policies, WAF attached, TLS policy). Use `mock_provider "aws"` with `override_data` for policy documents when needed. Test variable validations with `expect_failures`.
