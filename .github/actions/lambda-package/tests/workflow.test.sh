#!/usr/bin/env bash
# Static, isolated tests of .github/workflows/app-deploy.yml and of the runbook (EN-74 AC1 to AC6).
#
# They read files only (no AWS, no network, no YAML parser) and fail when the pipeline stops honouring an acceptance
# criterion: a gate turned back into an echo, a revert job removed, a wider role, an unexpected AWS call...
# Behaviour against a real account is verified by the dev deployment and the smoke tests (runbook, section Tests).
#
# Usage: bash .github/actions/lambda-package/tests/workflow.test.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "${here}/../../../.." && pwd)"
workflow="${repo}/.github/workflows/app-deploy.yml"
runbook="${repo}/docs/runbooks/app-deploy.md"
oidc_action="${repo}/.github/actions/aws-oidc/action.yml"
lambda_module="${repo}/infra/modules/lambda-service"

for file in "${workflow}" "${runbook}" "${oidc_action}"; do
  [ -f "${file}" ] || {
    echo "workflow.test: ${file#"${repo}"/} not found" >&2
    exit 2
  }
done

failures=0
total=0
skipped=0

check() {
  local name="$1"
  shift
  total=$((total + 1))
  if "$@"; then
    printf 'ok   %s\n' "${name}"
  else
    printf 'FAIL %s\n' "${name}" >&2
    failures=$((failures + 1))
  fi
}

skip() {
  skipped=$((skipped + 1))
  printf 'SKIP %s (%s)\n' "$1" "$2"
}

# Text of job $1 (from its "  <job>:" line to the next job).
job_block() {
  awk -v job="$1" '
    $0 == "  " job ":" { on = 1; print; next }
    on && /^  [a-z][a-z0-9-]*:$/ { exit }
    on { print }
  ' "${workflow}"
}

# Text of step "$2" in job $1 (from its "- name:" line to the next step).
step_block() {
  job_block "$1" | awk -v step="      - name: $2" '
    $0 == step { on = 1; print; next }
    on && /^      - name: / { exit }
    on { print }
  '
}

# Line number of step "$2" in job $1 inside the workflow.
step_line() {
  local job_start step_offset
  job_start="$(grep -n "^  $1:\$" "${workflow}" | cut -d: -f1)"
  step_offset="$(job_block "$1" | grep -n "^      - name: $2\$" | cut -d: -f1)"
  echo $((job_start + step_offset - 1))
}

# --- AC1: arm64 artifacts, new version -----------------------------------------------------------------------------

ac1_builds_with_package_action() {
  grep -q 'uses: ./.github/actions/lambda-package' "${workflow}"
}

ac1_refuses_non_arm64_function() {
  step_block deploy-lambda 'Upload artifacts and publish new versions' | grep -q 'Architectures\[0\]' \
    && step_block deploy-lambda 'Upload artifacts and publish new versions' | grep -q '!= arm64'
}

ac1_publishes_exact_artifact() {
  local block
  block="$(step_block deploy-lambda 'Upload artifacts and publish new versions')"
  grep -q 'update-function-code' <<< "${block}" \
    && grep -q 'publish-version .*--code-sha256' <<< "${block}"
}

# --- AC2: alias moves only after real pre-switch smoke tests ----------------------------------------------------------

ac2_pre_switch_invokes_new_version() {
  local block
  block="$(step_block deploy-lambda 'Pre-switch smoke tests')"
  grep -q 'aws lambda invoke' <<< "${block}" \
    && grep -q -- '--qualifier "\$new"' <<< "${block}" \
    && grep -q 'smoke-event.json' <<< "${block}" \
    && grep -q 'exit 1' <<< "${block}"
}

ac2_pre_switch_is_not_a_placeholder() {
  ! grep -q 'No pre-switch smoke tests defined' "${workflow}"
}

ac2_pre_switch_runs_before_switch() {
  local gate switch
  gate="$(step_line deploy-lambda 'Pre-switch smoke tests')"
  switch="$(step_line deploy-lambda 'Switch the alias live')"
  [ "${gate}" -lt "${switch}" ]
}

ac2_switch_only_when_something_was_published() {
  step_block deploy-lambda 'Switch the alias live' | grep -q "steps.publish.outputs.changed == 'true'"
}

# --- AC3: SPA and invalidation -------------------------------------------------------------------------------------------

ac3_spa_published_and_invalidated() {
  local block
  block="$(step_block publish-spa 'Publish the SPA')"
  grep -q 's3 sync spa/ "s3://${SPA_BUCKET}/"' <<< "${block}" \
    && grep -q 'cloudfront create-invalidation' <<< "${block}"
}

# --- AC4: rollback of aliases and SPA ---------------------------------------------------------------------------------

ac4_aliases_revert_on_failure() {
  local block
  block="$(step_block deploy-lambda 'Revert the aliases to the previous versions')"
  grep -q 'failure() || cancelled()' <<< "${block}" && grep -q 'update-alias' <<< "${block}"
}

ac4_spa_revert_job_waits_for_both_deployments() {
  local block
  block="$(job_block revert-spa)"
  grep -q 'needs: \[prepare, deploy-lambda, publish-spa\]' <<< "${block}" \
    && grep -q 'always()' <<< "${block}" \
    && grep -q "needs.deploy-lambda.result == 'failure'" <<< "${block}"
}

ac4_spa_revert_republishes_and_invalidates() {
  local block
  block="$(job_block revert-spa)"
  grep -q 's3 sync spa/ "s3://${SPA_BUCKET}/"' <<< "${block}" \
    && grep -q 'cloudfront create-invalidation' <<< "${block}" \
    && grep -q 'sha256sum --check' <<< "${block}"
}

ac4_spa_revert_target_is_recorded_before_publication() {
  local remember publish
  remember="$(step_line publish-spa 'Remember the live SPA')"
  publish="$(step_line publish-spa 'Publish the SPA')"
  [ "${remember}" -lt "${publish}" ] \
    && job_block publish-spa | grep -q 'restore_sha: ${{ steps.live.outputs.sha }}'
}

ac4_manual_rollback_jobs_exist() {
  [ -n "$(job_block rollback-lambda)" ] && step_block publish-spa 'Fetch the SPA to roll back to' | grep -q 'SHA256SUMS'
}

# --- AC5: no drift ---------------------------------------------------------------------------------------------------

ac5_pipeline_only_changes_code() {
  grep -q 'update-function-code' "${workflow}" && ! grep -q 'update-function-configuration' "${workflow}"
}

ac5_module_ignores_code_fields() {
  local attribute
  for attribute in filename source_code_hash s3_key s3_object_version function_version; do
    grep -rq "ignore_changes.*${attribute}\|^[[:space:]]*${attribute},\?\$" "${lambda_module}" --include='*.tf' || return 1
  done
  grep -rq 'ignore_changes' "${lambda_module}" --include='*.tf'
}

# --- AC6: least privilege -----------------------------------------------------------------------------------------------

# The role ARN is validated once, by the auth job; the four AWS jobs only consume its output.
ac6_uses_the_validated_role_only() {
  local count
  ! grep -q 'vars.AWS_DEPLOY_ROLE_ARN\|vars.AWS_APPLY_ROLE_ARN' <(job_block deploy-lambda; job_block publish-spa; job_block revert-spa; job_block rollback-lambda) || return 1
  count="$(grep -c 'role-to-assume: ${{ needs.auth.outputs.role_arn }}' "${workflow}")"
  [ "${count}" = 4 ]
}

# Dedicated role first; the IaC apply role of the same environment is only a named fallback (ADR-0016 decision).
ac6_role_names_are_pinned() {
  local block
  block="$(job_block auth)"
  grep -q 'role/sc-${TARGET_ENV}-app-deploy\$' <<< "${block}" \
    && grep -q 'role/sc-gha-apply-${TARGET_ENV}\$' <<< "${block}"
}

# --- ADR-0016: authentication modes ----------------------------------------------------------------------------------

# Workflow text without comment lines, to assert on commands rather than on explanations.
code_only() {
  grep -v '^[[:space:]]*#' "${workflow}"
}

auth_every_aws_job_follows_the_auth_job() {
  local job
  for job in deploy-lambda publish-spa revert-spa rollback-lambda; do
    job_block "${job}" | grep -q 'needs.auth.outputs.auth_mode' || {
      echo "${job} does not read the auth mode" >&2
      return 1
    }
    job_block "${job}" | grep -q 'environment: ${{ needs.prepare.outputs.target_env }}' || {
      echo "${job} is not bound to the environment" >&2
      return 1
    }
  done
}

auth_no_pull_request_trigger() {
  ! grep -qE '^  pull_request(_target)?:' "${workflow}" \
    && job_block auth | grep -q 'EVENT_NAME" != push' \
    && job_block auth | grep -q 'workflow_dispatch'
}

# A secret value only appears as an input of configure-aws-credentials, or as a boolean (`!= ''`) in the auth job.
auth_secrets_only_in_action_inputs() {
  local stray
  stray="$(code_only | grep 'secrets\.' \
    | grep -vE "^[[:space:]]+aws-(access-key-id|secret-access-key|session-token): \\$\\{\\{ secrets\\.AWS_(ACCESS_KEY_ID|SECRET_ACCESS_KEY|SESSION_TOKEN) \\}\\}\$" \
    | grep -vE "^[[:space:]]+HAS_[A-Z_]+: \\$\\{\\{ secrets\\.AWS_[A-Z_]+ != '' \\}\\}\$" || true)"
  [ -z "${stray}" ] || {
    echo "secret used outside the action inputs: ${stray}" >&2
    return 1
  }
  # Naming the secrets in a message is fine; expanding one in a command is not.
  ! code_only | grep -qE 'echo .*\$\{?(AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|AWS_SESSION_TOKEN)'
}

auth_secrets_steps_use_the_pinned_action() {
  local oidc_sha workflow_shas
  oidc_sha="$(grep -oE 'aws-actions/configure-aws-credentials@[0-9a-f]{40}' "${oidc_action}" | head -n1)"
  [ -n "${oidc_sha}" ] || return 1
  workflow_shas="$(grep -oE 'aws-actions/configure-aws-credentials@[^ ]+' "${workflow}" | sort -u)"
  [ "${workflow_shas}" = "${oidc_sha}" ] \
    && [ "$(grep -c 'uses: aws-actions/configure-aws-credentials@' "${workflow}")" = 4 ]
}

auth_oidc_has_priority() {
  local block oidc secrets
  block="$(step_block auth 'Select the AWS authentication mode')"
  oidc="$(grep -n '^ *mode=oidc$' <<< "${block}" | cut -d: -f1)"
  secrets="$(grep -n '^ *mode=secrets$' <<< "${block}" | cut -d: -f1)"
  [ -n "${oidc}" ] && [ -n "${secrets}" ] && [ "${oidc}" -lt "${secrets}" ] \
    && grep -q 'APPLY_ROLE_ARN' <<< "${block}"
}

auth_secrets_are_dev_from_develop_only() {
  local block
  block="$(step_block auth 'Select the AWS authentication mode')"
  grep -q 'refs/heads/develop' <<< "${block}" && grep -qF '"$TARGET_ENV" != dev' <<< "${block}"
}

auth_unconfigured_skips_only_a_dev_push() {
  local block
  block="$(step_block auth 'Select the AWS authentication mode')"
  grep -qF '"$TARGET_ENV" = dev ] && [ "$EVENT_NAME" = push ]' <<< "${block}" \
    && grep -q 'notice title=Deployment skipped' <<< "${block}" \
    && grep -q 'error title=Deployment not configured' <<< "${block}"
}

auth_incomplete_secrets_fail() {
  step_block auth 'Select the AWS authentication mode' | grep -q 'Incomplete credentials'
}

# --- Blocking review points: nothing deployed is a failure, bucket checks fit the least-privilege policy ----------

prepare_fails_when_nothing_is_deployable() {
  local block
  block="$(step_block prepare 'Resolve environment, mode and work to do')"
  grep -q 'title=Nothing to deploy' <<< "${block}" \
    && grep -q 'title=Service not deployable' <<< "${block}" \
    && grep -q 'git diff --name-only' <<< "${block}"
}

prepare_checkout_can_diff_the_push() {
  job_block prepare | grep -q 'fetch-depth: 0'
}

bucket_checks_do_not_use_head_bucket() {
  ! code_only | grep -q 'head-bucket'
}

bucket_checks_list_under_the_env_prefix() {
  local block
  block="$(step_block deploy-lambda 'Check the artifacts bucket owner')"
  grep -q 'list-objects-v2 --bucket "\$ARTIFACTS_BUCKET" --expected-bucket-owner "\$account"' <<< "${block}" \
    && grep -qF -- '--prefix "${TARGET_ENV}/"' <<< "${block}" \
    && [ "$(code_only | grep -c 'list-objects-v2 --bucket "\$ARTIFACTS_BUCKET"')" = 3 ] \
    && [ "$(code_only | grep -c 'list-objects-v2 --bucket "\$SPA_BUCKET"')" = 2 ]
}

# Every AWS API the workflow calls is documented in the runbook as an allowed action, and nothing else is.
ac6_workflow_calls_match_documented_actions() {
  local sub action
  declare -A lambda_actions=(
    [get-alias]=lambda:GetAlias
    [get-function-configuration]=lambda:GetFunctionConfiguration
    [update-function-code]=lambda:UpdateFunctionCode
    [publish-version]=lambda:PublishVersion
    [update-alias]=lambda:UpdateAlias
    [invoke]=lambda:InvokeFunction
    [wait]=lambda:GetFunction
  )
  while read -r sub; do
    action="${lambda_actions[${sub}]:-}"
    [ -n "${action}" ] || {
      echo "undocumented: aws lambda ${sub}" >&2
      return 1
    }
    grep -qw "${action}" "${runbook}" || {
      echo "not in the runbook: ${action}" >&2
      return 1
    }
  done < <(grep -oE 'aws lambda [a-z-]+' "${workflow}" | awk '{print $3}' | sort -u)

  while read -r sub; do
    [ "${sub}" = create-invalidation ] || {
      echo "undocumented: aws cloudfront ${sub}" >&2
      return 1
    }
  done < <(grep -oE 'aws cloudfront [a-z-]+' "${workflow}" | awk '{print $3}' | sort -u)
  grep -q 'cloudfront:CreateInvalidation' "${runbook}" || return 1

  # s3api calls: only put-object (s3:PutObject) and list-objects-v2 (s3:ListBucket, with the s3:prefix condition).
  while read -r sub; do
    case "${sub}" in
      put-object) action=s3:PutObject ;;
      list-objects-v2) action=s3:ListBucket ;;
      *)
        echo "undocumented: aws s3api ${sub}" >&2
        return 1
        ;;
    esac
    grep -qw "${action}" "${runbook}" || {
      echo "not in the runbook: ${action}" >&2
      return 1
    }
  done < <(code_only | grep -oE 'aws s3api [a-z0-9-]+' | awk '{print $3}' | sort -u)
  grep -q 's3:prefix' "${runbook}" && grep -q 'HeadBucket' "${runbook}"
}

ac6_runbook_documents_boundary_and_trust() {
  grep -q 'permissions boundary' "${runbook}" && grep -q 'environment:<env>' "${runbook}" && grep -q 's3:ResourceAccount' "${runbook}"
}

# --- Cross-cutting: ADR-0013 region and "never a silent no-op" -----------------------------------------------------------

region_defaults_to_us_east_1() {
  ! grep -q 'eu-west-3' "${workflow}" "${oidc_action}" "${runbook}" || return 1
  # Four jobs x two modes (OIDC and session credentials).
  [ "$(grep -c "vars.AWS_REGION || 'us-east-1'" "${workflow}")" = 8 ] \
    && grep -q 'default: us-east-1' "${oidc_action}"
}

# A missing bucket or distribution variable fails the job that needs it; missing authentication fails in `auth`
# (the only skip is a dev push, tested separately).
missing_configuration_fails() {
  local job
  for job in deploy-lambda publish-spa revert-spa; do
    step_block "${job}" 'Check configuration' | grep -q 'Missing variable' || return 1
    step_block "${job}" 'Check configuration' | grep -q 'exit 1' || return 1
  done
  step_block auth 'Select the AWS authentication mode' | grep -q 'Deployment not configured'
}

check 'EN-74-AC1 every service is built by the lambda-package action' ac1_builds_with_package_action
check 'EN-74-AC1 a function that is not arm64 stops the deployment' ac1_refuses_non_arm64_function
check 'EN-74-AC1 the published version is exactly the built artifact' ac1_publishes_exact_artifact
check 'EN-74-AC2 pre-switch smoke tests invoke the new immutable version and can fail the run' ac2_pre_switch_invokes_new_version
check 'EN-74-AC2 the pre-switch gate is not a placeholder' ac2_pre_switch_is_not_a_placeholder
check 'EN-74-AC2 the pre-switch gate runs before the alias moves' ac2_pre_switch_runs_before_switch
check 'EN-74-AC2 the alias only moves when a version was published' ac2_switch_only_when_something_was_published
check 'EN-74-AC3 the SPA is synced to the bucket and CloudFront is invalidated' ac3_spa_published_and_invalidated
check 'EN-74-AC4 aliases revert on failure or cancellation' ac4_aliases_revert_on_failure
check 'EN-74-AC4 the SPA revert job waits for both deployments and runs on failure' ac4_spa_revert_job_waits_for_both_deployments
check 'EN-74-AC4 the SPA revert verifies, republishes and invalidates' ac4_spa_revert_republishes_and_invalidates
check 'EN-74-AC4 the SPA to restore is recorded before the bucket is touched' ac4_spa_revert_target_is_recorded_before_publication
check 'EN-74-AC4 manual rollback of Lambda and SPA still exists' ac4_manual_rollback_jobs_exist
check 'EN-74-AC5 the pipeline only updates function code, never configuration' ac5_pipeline_only_changes_code
if [ -d "${lambda_module}" ]; then
  check 'EN-74-AC5 the lambda-service module ignores the code fields and the alias version' ac5_module_ignores_code_fields
else
  skip 'EN-74-AC5 the lambda-service module ignores the code fields and the alias version' 'infra/modules/lambda-service not in this checkout'
fi
check 'EN-74-AC6 every OIDC step uses the role ARN validated by the auth job' ac6_uses_the_validated_role_only
check 'EN-74-AC6 the role names sc-<env>-app-deploy and sc-gha-apply-<env> are enforced by the auth job' ac6_role_names_are_pinned
check 'EN-74-AC6 AWS calls of the workflow equal the actions documented for the role' ac6_workflow_calls_match_documented_actions
check 'EN-74-AC6 the runbook documents boundary, trust and account condition' ac6_runbook_documents_boundary_and_trust
check 'EN-74-ADR0013 every region default is us-east-1' region_defaults_to_us_east_1
check 'EN-74-CFG missing configuration fails the deployment and rollback jobs' missing_configuration_fails
check 'EN-74-AUTH every AWS job is bound to the environment and follows the auth job' auth_every_aws_job_follows_the_auth_job
check 'EN-74-AUTH no pull_request trigger, only push and workflow_dispatch may authenticate' auth_no_pull_request_trigger
check 'EN-74-AUTH secrets only reach configure-aws-credentials inputs and are never echoed' auth_secrets_only_in_action_inputs
check 'EN-74-AUTH the secrets mode uses the same pinned action as aws-oidc' auth_secrets_steps_use_the_pinned_action
check 'EN-74-AUTH OIDC takes priority over the session credentials' auth_oidc_has_priority
check 'EN-74-AUTH session credentials are accepted for dev from develop only' auth_secrets_are_dev_from_develop_only
check 'EN-74-AUTH nothing configured skips a dev push with a notice and fails otherwise' auth_unconfigured_skips_only_a_dev_push
check 'EN-74-AUTH a partial set of session credentials fails' auth_incomplete_secrets_fail
check 'EN-74-REVIEW1 a run that deploys nothing fails in prepare' prepare_fails_when_nothing_is_deployable
check 'EN-74-REVIEW1 prepare can diff the pushed range' prepare_checkout_can_diff_the_push
check 'EN-74-REVIEW2 no head-bucket call remains' bucket_checks_do_not_use_head_bucket
check 'EN-74-REVIEW2 bucket owner checks list under the environment prefix' bucket_checks_list_under_the_env_prefix

printf '\n%s/%s workflow cases passed' "$((total - failures))" "${total}"
[ "${skipped}" = 0 ] || printf ' (%s skipped)' "${skipped}"
printf '\n'
[ "${failures}" = 0 ]
