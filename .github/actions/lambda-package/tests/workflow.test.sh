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

ac6_uses_the_dedicated_role_only() {
  local count
  ! grep -q 'AWS_APPLY_ROLE_ARN' "${workflow}" || return 1
  count="$(grep -c 'role-to-assume: ${{ vars.AWS_DEPLOY_ROLE_ARN }}' "${workflow}")"
  [ "${count}" = 4 ]
}

ac6_role_name_is_pinned() {
  [ "$(grep -c 'role/sc-${TARGET_ENV}-app-deploy' "${workflow}")" = 4 ]
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
  grep -q 'cloudfront:CreateInvalidation' "${runbook}"
}

ac6_runbook_documents_boundary_and_trust() {
  grep -q 'permissions boundary' "${runbook}" && grep -q 'environment:<env>' "${runbook}" && grep -q 's3:ResourceAccount' "${runbook}"
}

# --- Cross-cutting: ADR-0013 region and "never a silent no-op" -----------------------------------------------------------

region_defaults_to_us_east_1() {
  ! grep -q 'eu-west-3' "${workflow}" "${oidc_action}" "${runbook}" || return 1
  [ "$(grep -c "vars.AWS_REGION || 'us-east-1'" "${workflow}")" = 4 ] \
    && grep -q 'default: us-east-1' "${oidc_action}"
}

missing_configuration_fails() {
  local job
  ! grep -q 'Deployment skipped\|Rollback skipped\|Not configured' "${workflow}" || return 1
  for job in deploy-lambda publish-spa revert-spa rollback-lambda; do
    step_block "${job}" 'Check configuration' | grep -q 'AWS_DEPLOY_ROLE_ARN is not set' || return 1
    step_block "${job}" 'Check configuration' | grep -q 'exit 1' || return 1
  done
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
check 'EN-74-AC6 every AWS job assumes the dedicated deploy role, never the apply role' ac6_uses_the_dedicated_role_only
check 'EN-74-AC6 the role name sc-<env>-app-deploy is enforced in every job' ac6_role_name_is_pinned
check 'EN-74-AC6 AWS calls of the workflow equal the actions documented for the role' ac6_workflow_calls_match_documented_actions
check 'EN-74-AC6 the runbook documents boundary, trust and account condition' ac6_runbook_documents_boundary_and_trust
check 'EN-74-ADR0013 every region default is us-east-1' region_defaults_to_us_east_1
check 'EN-74-CFG missing configuration fails the deployment and rollback jobs' missing_configuration_fails

printf '\n%s/%s workflow cases passed' "$((total - failures))" "${total}"
[ "${skipped}" = 0 ] || printf ' (%s skipped)' "${skipped}"
printf '\n'
[ "${failures}" = 0 ]
