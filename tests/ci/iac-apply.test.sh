#!/usr/bin/env bash
# Contract tests of .github/workflows/iac-apply.yml (EN-73). Static checks on the workflow text plus an execution
# of the real `target` step script for each (event, ref) pair. No network, no AWS, no OpenTofu.
#
#   bash tests/ci/iac-apply.test.sh
#
# Uses `yq` (mikefarah, v4) for a few structural checks when it is on the PATH, and falls back to grep otherwise.
# Test names start with the acceptance criterion they cover (EN-73-AC1 ... AC5), see docs/runbooks/iac-apply.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKFLOW="${ROOT}/.github/workflows/iac-apply.yml"

pass=0
fail=0
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

ok() {
  pass=$((pass + 1))
  printf 'ok   %s\n' "$1"
}

ko() {
  fail=$((fail + 1))
  printf 'FAIL %s\n' "$1"
}

# check "<name>" <command...>: the test passes when the command succeeds.
check() {
  local name="$1"
  shift
  if "$@" > /dev/null 2>&1; then
    ok "${name}"
  else
    ko "${name}"
  fi
}

has_yq() { command -v yq > /dev/null 2>&1; }

# count_fixed <fixed string>: number of lines of the workflow containing the string.
count_fixed() { grep -cF -- "$1" "${WORKFLOW}" || true; }

# count_is <fixed string> <expected>
count_is() { [ "$(count_fixed "$1")" -eq "$2" ]; }

# job_block <job id>: lines of one top-level job.
job_block() {
  awk -v job="  $1:" '
    $0 == job { in_job = 1; print; next }
    in_job && /^  [A-Za-z0-9_-]+:/ { exit }
    in_job { print }
  ' "${WORKFLOW}"
}

# target_script: the `run` script of the step that resolves the environment, de-indented.
target_script() {
  awk '
    /^      - name: Resolve the target environment$/ { in_step = 1; next }
    in_step && /^        run: \|$/ { in_run = 1; next }
    in_run {
      if ($0 ~ /^          /) { sub(/^          /, ""); print; next }
      if ($0 ~ /^$/) { print ""; next }
      exit
    }
  ' "${WORKFLOW}"
}

# run_target <event> <ref>: runs the real script, prints the resolved env (empty on refusal), returns its status.
run_target() {
  local out="${tmp}/github_output"
  : > "${out}"
  target_script > "${tmp}/target.sh"
  local rc=0
  EVENT_NAME="$1" REF="$2" GITHUB_OUTPUT="${out}" bash "${tmp}/target.sh" > /dev/null 2>&1 || rc=$?
  sed -n 's/^env=//p' "${out}"
  return "${rc}"
}

expect_target() { # <event> <ref> <expected env>
  local got
  got="$(run_target "$1" "$2")" || return 1
  [ "${got}" = "$3" ]
}

expect_refused() { # <event> <ref>
  local got rc=0
  got="$(run_target "$1" "$2")" || rc=$?
  [ "${rc}" -ne 0 ] && [ -z "${got}" ]
}

# plan_files: every plan path used by the workflow, apart from the cleanup glob.
plan_files() { grep -v 'rm -f' "${WORKFLOW}" | grep -o 'apply-[^" ]*\.tfplan' | sort -u; }

push_branches() {
  if has_yq; then
    yq -r '.on.push.branches[]' "${WORKFLOW}" | sort | paste -sd, -
  else
    awk '/^    branches:$/ { b = 1; next } b && /^      - / { sub(/^      - /, ""); print; next } b { exit }' "${WORKFLOW}" | sort | paste -sd, -
  fi
}

dispatch_has_no_inputs() {
  if has_yq; then
    [ "$(yq -r '.on.workflow_dispatch.inputs // "none"' "${WORKFLOW}")" = "none" ]
  else
    grep -Eq '^  workflow_dispatch: \{\}$' "${WORKFLOW}"
  fi
}

concurrency_never_cancels() {
  if has_yq; then
    [ "$(yq -r '.concurrency."cancel-in-progress"' "${WORKFLOW}")" = "false" ]
  else
    grep -Eq '^  cancel-in-progress: false$' "${WORKFLOW}"
  fi
}

top_level_permissions_empty() {
  if has_yq; then
    [ "$(yq -r '.permissions | length' "${WORKFLOW}")" = "0" ]
  else
    grep -Eq '^permissions: \{\}$' "${WORKFLOW}"
  fi
}

target_job_has_no_credentials() {
  local block
  block="$(job_block target)"
  [ -n "${block}" ] && ! grep -Eq 'environment:|id-token:|uses:' <<< "${block}"
}

# never_matches <grep options and pattern>: no non-comment line of the workflow matches.
never_matches() {
  local n
  n="$(grep -v '^[[:space:]]*#' "${WORKFLOW}" | grep -c "$@" || true)"
  [ "${n}" -eq 0 ]
}

no_artifact_or_cache() {
  ! grep -Eq '^[[:space:]]*uses:.*(upload-artifact|download-artifact|actions/cache)' "${WORKFLOW}"
}

# Each stack job writes the plan with OUT=<file> and applies PLAN=<same variable> in its own steps.
plan_and_apply_share_jobs() {
  local job block
  for job in apply-foundation apply-platform; do
    block="$(job_block "${job}")"
    grep -qF 'OUT="${plan_file}"' <<< "${block}" || return 1
    grep -qF 'PLAN="${plan_file}"' <<< "${block}" || return 1
  done
}

# In each stack job the "Plan summary" step comes before the "Apply the saved plan" step.
plan_summary_precedes_apply() {
  local job block summary apply
  for job in apply-foundation apply-platform; do
    block="$(job_block "${job}")"
    summary="$(grep -nF 'name: Plan summary (' <<< "${block}" | head -n 1 | cut -d: -f1)"
    apply="$(grep -nF 'name: Apply the saved plan (' <<< "${block}" | head -n 1 | cut -d: -f1)"
    [ -n "${summary}" ] && [ -n "${apply}" ] && [ "${summary}" -lt "${apply}" ] || return 1
  done
}

# Only actions and addresses are extracted from the plan JSON; never before/after attribute values.
plan_summary_has_no_values() {
  grep -qF '"\(.change.actions | join("+")) \(.address)"' "${WORKFLOW}" &&
    ! grep -qE '\.change\.(after|before)|after_sensitive|before_sensitive' "${WORKFLOW}"
}

# --- Preconditions -----------------------------------------------------------------------------------------------

check "workflow file exists" test -f "${WORKFLOW}"
check "the target step script can be extracted" test -n "$(target_script)"

# --- EN-73-AC1: develop -> dev, foundation then platform, apply role of the environment ------------------------

check "EN-73-AC1 push triggers are develop and main only" test "$(push_branches)" = "develop,main"
check "EN-73-AC1 push on develop resolves to dev" expect_target push refs/heads/develop dev
check "EN-73-AC1 manual run on develop resolves to dev" expect_target workflow_dispatch refs/heads/develop dev
check "EN-73-AC1 apply is limited to infra/** changes" grep -qE '^      - infra/\*\*$' "${WORKFLOW}"
check "EN-73-AC1 platform waits for foundation" grep -qE 'needs: \[target, apply-foundation\]' "${WORKFLOW}"
check "EN-73-AC1 foundation job needs only target" grep -qE '^    needs: target$' "${WORKFLOW}"
check "EN-73-AC1 both stack jobs assume the apply role of the environment" count_is "role-to-assume: \${{ vars.AWS_APPLY_ROLE_ARN }}" 2
check "EN-73-AC1 no plan role and no long-lived key" never_matches -E 'AWS_PLAN_ROLE_ARN|AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY'
check "EN-73-AC1 region fallback is us-east-1 in both stack jobs" count_is "aws-region: \${{ vars.AWS_REGION || 'us-east-1' }}" 2
check "EN-73-AC1 no eu-west-3 fallback left" never_matches -e 'eu-west-3'

# --- EN-73-AC2: main -> prod behind the environment approval; manual runs never reach prod ---------------------

check "EN-73-AC2 push on main resolves to prod" expect_target push refs/heads/main prod
check "EN-73-AC2 manual run on main is refused" expect_refused workflow_dispatch refs/heads/main
check "EN-73-AC2 manual run on another branch is refused" expect_refused workflow_dispatch refs/heads/feature/x
check "EN-73-AC2 push on another branch is refused" expect_refused push refs/heads/feature/x
check "EN-73-AC2 manual run takes no input (the target cannot be chosen)" dispatch_has_no_inputs
check "EN-73-AC2 both stack jobs are bound to the resolved environment" count_is "    environment: \${{ needs.target.outputs.env }}" 2
check "EN-73-AC2 target job has no environment, no OIDC and no action" target_job_has_no_credentials
check "EN-73-AC2 id-token: write only in the two environment-bound jobs" count_is "      id-token: write" 2
check "EN-73-AC2 no pull_request_target" never_matches -e 'pull_request_target'
check "EN-73-AC2 top-level permissions are empty" top_level_permissions_empty

# --- EN-73-AC3: frozen plan, no plan artifact, stale plan and stale run rejected ------------------------------

check "EN-73-AC3 plan and apply use one plan file path" test "$(plan_files)" = 'apply-${STACK}.tfplan'
check "EN-73-AC3 plan step writes the file in both stack jobs" count_is 'task plan ENV="${TARGET_ENV}" STACK="${STACK}" OUT="${plan_file}"' 2
check "EN-73-AC3 apply step applies that same file in both stack jobs" count_is 'task apply ENV="${TARGET_ENV}" STACK="${STACK}" PLAN="${plan_file}"' 2
check "EN-73-AC3 plan and apply run in the same job (no plan transfer)" plan_and_apply_share_jobs
check "EN-73-AC3 no artifact and no cache action" no_artifact_or_cache
check "EN-73-AC3 no -auto-approve" never_matches -e '-auto-approve'
check "EN-73-AC3 stale plan is reported in both stack jobs" count_is "grep -qi 'saved plan is stale'" 2
check "EN-73-AC3 stale run is refused in both stack jobs" count_is "::error title=Stale run::" 2
check "EN-73-AC3 plan summary runs before the apply in both stack jobs" plan_summary_precedes_apply
check "EN-73-AC3 plan summary lists actions and addresses, not values" plan_summary_has_no_values

# --- EN-73-AC4: concurrency --------------------------------------------------------------------------------------

check "EN-73-AC4 concurrency group is per environment" grep -qE "^  group: iac-apply-" "${WORKFLOW}"
check "EN-73-AC4 only a push on main joins the prod group" grep -qF "github.ref == 'refs/heads/main' && github.event_name == 'push'" "${WORKFLOW}"
check "EN-73-AC4 refused runs get a unique group" grep -qF "format('rejected-{0}', github.run_id)" "${WORKFLOW}"
check "EN-73-AC4 a running apply is never cancelled" concurrency_never_cancels
check "EN-73-AC4 every job has a timeout" test "$(grep -cE '^    timeout-minutes:' "${WORKFLOW}")" -eq 3

# --- EN-73-AC5: traceability -------------------------------------------------------------------------------------

check "EN-73-AC5 summary shows the environment in both stack jobs" count_is '| Environment | \`${TARGET_ENV}\` |' 2
check "EN-73-AC5 summary shows the commit in both stack jobs" count_is '| Commit | \`${GITHUB_SHA}\` |' 2
check "EN-73-AC5 summary shows the pull request in both stack jobs" count_is '| Pull request | ${pr} |' 2
check "EN-73-AC5 summary shows plan and apply outcomes in both stack jobs" test "$(grep -cE '^              echo "\| (Plan|Apply) \| \$\{(PLAN|APPLY)_OUTCOME\} \|"$' "${WORKFLOW}")" -eq 4
check "EN-73-AC5 summary is written even when a step fails" test "$(grep -cE '^      - name: Job summary$' "${WORKFLOW}")" -eq 2
check "EN-73-AC5 commit message is untrusted and goes through env" count_is 'HEAD_MESSAGE: ${{ github.event.head_commit.message }}' 2

printf '\n%d passed, %d failed\n' "${pass}" "${fail}"
[ "${fail}" -eq 0 ]
