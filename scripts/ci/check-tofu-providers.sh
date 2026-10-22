#!/usr/bin/env bash
# Pre-flight gate of the PR plan (iac-plan, EN-72). Run it BEFORE any AWS credential exists.
#
# A pull request controls the HCL, so it controls which providers and modules `tofu init` downloads and which
# data sources run during `tofu plan` (all of them with the plan role credentials). This script:
#   1. refuses constructs that execute arbitrary code or reach arbitrary endpoints at plan time (data "external",
#      data "http", provisioners, external encryption key_provider/method) in *.tf, *.tofu and their .json forms;
#   2. downloads the providers into a fixed plugin cache with `tofu init -backend=false` (no credentials yet);
#   3. fails if the providers (tofu providers, lock file) are not on the allowlist, or if a module is not local.
# The credentialed `tofu init` that follows must use `-plugin-dir` on the same cache so nothing is downloaded
# once the role is assumed (see iac-plan.yml).
#
# Usage: TF_PLUGIN_CACHE_DIR=<dir> scripts/ci/check-tofu-providers.sh <stack>
# Needs: tofu, jq, grep, find. Run from the repository root.
set -euo pipefail

# Providers a stack may use. Keep in sync with required_providers in infra/.
ALLOWED_PROVIDERS=(
  "registry.opentofu.org/hashicorp/aws"
  "registry.opentofu.org/hashicorp/random"
  "registry.opentofu.org/hashicorp/archive"
)

fail() {
  echo "::error title=Plan pre-flight failed::$1" >&2
  exit 1
}

stack="${1:-}"
case "${stack}" in
  '' | *[!a-z0-9-]*) echo "usage: $0 <stack> (lowercase letters, digits and dashes)" >&2; exit 2 ;;
  *) ;;
esac
: "${TF_PLUGIN_CACHE_DIR:?TF_PLUGIN_CACHE_DIR must point to a directory outside the repository}"

dir="infra/stacks/${stack}"
if [ ! -d "${dir}" ]; then
  echo "pre-flight: ${dir} not found, nothing to check"
  mkdir -p "${TF_PLUGIN_CACHE_DIR}"
  exit 0
fi
command -v jq >/dev/null 2>&1 || fail "jq is required"

is_allowed() {
  local candidate="$1" p
  for p in "${ALLOWED_PROVIDERS[@]}"; do
    if [ "${candidate}" = "${p}" ]; then
      return 0
    fi
  done
  return 1
}

# Reads one provider address per line on stdin, fails on the first one outside the allowlist.
require_allowed() {
  local origin="$1" count=0 addr
  while IFS= read -r addr; do
    [ -n "${addr}" ] || continue
    count=$((count + 1))
    if ! is_allowed "${addr}"; then
      fail "provider '${addr}' (${origin}) is not on the allowlist (${ALLOWED_PROVIDERS[*]})."
    fi
  done
  echo "${count}"
}

echo "==> pre-flight ${stack}: forbidden constructs"
rc=0
hits="$(grep -rEnI --exclude-dir=.terraform \
  --include='*.tf' --include='*.tf.json' --include='*.tofu' --include='*.tofu.json' \
  -e 'data[[:space:]]+"(external|http)"' \
  -e 'provisioner[[:space:]]+"' \
  -e '(key_provider|method)[[:space:]]+"external"' \
  infra/ | cut -d: -f1,2)" || rc=$?
case "${rc}" in
  0) echo "${hits}" >&2; fail "data \"external\"/\"http\", provisioner blocks and external encryption key_provider/method blocks are forbidden under infra/ (locations above)." ;;
  1) ;;
  *) fail "grep failed while scanning infra/ (exit ${rc})." ;;
esac
json_files="$(find infra \( -name '*.tf.json' -o -name '*.tofu.json' \) -not -path '*/.terraform/*' -print)"
if [ -n "${json_files}" ]; then
  echo "${json_files}" >&2
  fail "*.tf.json and *.tofu.json files are not allowed under infra/ (the scans above only read HCL)."
fi

echo "==> pre-flight ${stack}: tofu init -backend=false (plugin cache ${TF_PLUGIN_CACHE_DIR})"
mkdir -p "${TF_PLUGIN_CACHE_DIR}"
tofu -chdir="${dir}" init -backend=false -input=false -no-color

echo "==> pre-flight ${stack}: provider allowlist"
# `tofu providers` only reads the configuration, it never starts a provider. Lines look like
# `├── provider[registry.opentofu.org/hashicorp/aws] ~> 6.0`.
listing="$(tofu -chdir="${dir}" providers -no-color)"
found="$(printf '%s\n' "${listing}" | { grep -oE 'provider\[[^]]+\]' || true; } | sed -E 's/^provider\[(.*)\]$/\1/' | sort -u)"
n="$(printf '%s\n' "${found}" | require_allowed "tofu providers")"
if [ "${n}" -eq 0 ]; then
  fail "tofu providers listed no provider for ${stack}: cannot verify the allowlist."
fi

lock="${dir}/.terraform.lock.hcl"
if [ -f "${lock}" ]; then
  locked="$({ grep -E '^provider "' "${lock}" || true; } | sed -E 's/^provider "([^"]+)".*/\1/' | sort -u)"
  printf '%s\n' "${locked}" | require_allowed "lock file" >/dev/null
fi

echo "==> pre-flight ${stack}: modules"
modules="${dir}/.terraform/modules/modules.json"
if [ -f "${modules}" ]; then
  remote="$(jq -r '.Modules[]?.Source // empty | select((startswith("./") or startswith("../")) | not)' "${modules}")"
  if [ -n "${remote}" ]; then
    echo "${remote}" >&2
    fail "only local modules (./ or ../) are allowed, found remote sources above."
  fi
fi

echo "pre-flight ${stack}: OK (${n} provider(s) on the allowlist)"
