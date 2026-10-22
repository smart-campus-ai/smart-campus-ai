#!/usr/bin/env bash
# Isolated tests of .github/actions/lambda-package/package.sh (EN-74 AC1 and the supply-chain rules around it).
#
# No network, no AWS, no real pip: `python` is replaced by a stub that records its arguments. Each case runs in its own
# throw-away workspace. Needs a GNU userland (bash, coreutils, findutils, zip, unzip, file, openssl), as on ubuntu runners.
#
# Usage: bash .github/actions/lambda-package/tests/package.test.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package_sh="${here}/../package.sh"

for tool in zip unzip file openssl sha256sum base64; do
  command -v "${tool}" > /dev/null || {
    echo "package.test: ${tool} is required" >&2
    exit 2
  }
done

root="$(mktemp -d)"
trap 'rm -rf "${root}"' EXIT

touch -d '2020-01-01 00:00:00 UTC' "${root}" 2> /dev/null || {
  echo "package.test: GNU touch/find are required (run on linux)" >&2
  exit 2
}

failures=0
total=0

# --- helpers -----------------------------------------------------------------------------------------------------

# New workspace with a python stub first in PATH. Prints its path.
new_workspace() {
  local ws
  ws="$(mktemp -d "${root}/ws.XXXXXX")"
  mkdir -p "${ws}/bin" "${ws}/services"
  cat > "${ws}/bin/python" << 'STUB'
#!/usr/bin/env bash
# Stub for `python -m pip install ...`: records the arguments and drops one file in --target.
printf '%s\n' "$*" >> "${FAKE_PYTHON_LOG:?}"
target=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --target) target="$2"; shift 2 ;;
    *) shift ;;
  esac
done
mkdir -p "${target}/fakedep"
echo "VALUE = 1" > "${target}/fakedep/__init__.py"
STUB
  chmod +x "${ws}/bin/python"
  : > "${ws}/pip.log"
  printf '%s' "${ws}"
}

# New python service in workspace $1 named $2; the requirements content is read from stdin.
new_python_service() {
  local ws="$1" svc="$2"
  mkdir -p "${ws}/services/${svc}/tests"
  printf 'def handler(event, context):\n    return {"statusCode": 200}\n' > "${ws}/services/${svc}/handler.py"
  printf 'def test_handler():\n    pass\n' > "${ws}/services/${svc}/tests/test_handler.py"
  cat > "${ws}/services/${svc}/requirements.txt"
}

# Runs package.sh for service $2 in workspace $1, output in $1/${3:-out}. Stderr goes to $1/stderr.
run_package() {
  local ws="$1" svc="$2" out="${3:-out}"
  (
    cd "${ws}"
    PATH="${ws}/bin:${PATH}" SERVICE="${svc}" OUTPUT_DIR="${out}" FAKE_PYTHON_LOG="${ws}/pip.log" \
      GITHUB_OUTPUT="${ws}/github_output" bash "${package_sh}" > "${ws}/stdout" 2> "${ws}/stderr"
  )
}

# ELF64 header only (64 bytes) for the machine given as printf %b octal escapes.
make_elf() {
  local file="$1" machine="$2"
  {
    printf '\177ELF\002\001\001\000\000\000\000\000\000\000\000\000' # e_ident: 64-bit, little endian
    printf '\003\000'                                               # ET_DYN
    printf '%b' "${machine}"                                        # e_machine
    printf '\001\000\000\000'                                       # EV_CURRENT
    head -c 28 /dev/zero                                            # entry, phoff, shoff, flags
    printf '\100\000'                                               # e_ehsize
    head -c 10 /dev/zero
  } > "${file}"
}
elf_x86_64='\0076\0000'
elf_aarch64='\0267\0000'

hex_a="$(printf 'a%.0s' {1..64})"
hex_b="$(printf 'b%.0s' {1..64})"

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

# --- cases -------------------------------------------------------------------------------------------------------

case_zip_and_checksum() {
  local ws
  ws="$(new_workspace)"
  new_python_service "${ws}" tickets <<< '# no dependency' || return 1
  run_package "${ws}" tickets || return 1
  [ -f "${ws}/out/tickets.zip" ] || return 1
  # The .sha256 file is in sha256sum format and matches the zip.
  (cd "${ws}/out" && sha256sum --check --strict --quiet tickets.zip.sha256) || return 1
  # The handler ships, tests and bytecode do not.
  local listing
  listing="$(unzip -Z1 "${ws}/out/tickets.zip")"
  grep -qx 'handler.py' <<< "${listing}" || return 1
  ! grep -q 'test_handler' <<< "${listing}" || return 1
  ! grep -q '__pycache__' <<< "${listing}" || return 1
}

case_outputs_match_zip() {
  local ws expected
  ws="$(new_workspace)"
  new_python_service "${ws}" kpi <<< '# no dependency' || return 1
  run_package "${ws}" kpi || return 1
  # code_sha256 is the base64 digest Lambda reports as CodeSha256: the deploy job compares it to the live version.
  expected="$(openssl dgst -sha256 -binary "${ws}/out/kpi.zip" | base64 | tr -d '\n')"
  grep -qx "code_sha256=${expected}" "${ws}/github_output" || return 1
  grep -qx 'runtime=python' "${ws}/github_output" || return 1
}

case_reproducible_zip() {
  local ws first second
  ws="$(new_workspace)"
  new_python_service "${ws}" tickets <<< '# no dependency' || return 1
  run_package "${ws}" tickets out1 || return 1
  # Same content, different mtime: the zip must not change.
  touch -d '2024-06-01 12:00:00 UTC' "${ws}/services/tickets/handler.py"
  run_package "${ws}" tickets out2 || return 1
  first="$(sha256sum "${ws}/out1/tickets.zip" | cut -d' ' -f1)"
  second="$(sha256sum "${ws}/out2/tickets.zip" | cut -d' ' -f1)"
  [ "${first}" = "${second}" ] || return 1
}

case_content_change_changes_zip() {
  local ws first second
  ws="$(new_workspace)"
  new_python_service "${ws}" tickets <<< '# no dependency' || return 1
  run_package "${ws}" tickets out1 || return 1
  echo '# changed' >> "${ws}/services/tickets/handler.py"
  run_package "${ws}" tickets out2 || return 1
  first="$(sha256sum "${ws}/out1/tickets.zip" | cut -d' ' -f1)"
  second="$(sha256sum "${ws}/out2/tickets.zip" | cut -d' ' -f1)"
  [ "${first}" != "${second}" ] || return 1
}

case_pip_targets_arm64_with_hashes() {
  local ws args
  ws="$(new_workspace)"
  new_python_service "${ws}" tickets << EOF || return 1
boto3-stub==1.0.0 \\
    --hash=sha256:${hex_a} \\
    --hash=sha256:${hex_b}
EOF
  run_package "${ws}" tickets || return 1
  args="$(cat "${ws}/pip.log")"
  # aarch64 wheels only, binary only, hashes enforced.
  grep -q -- '--platform manylinux2014_aarch64' <<< "${args}" || return 1
  grep -q -- '--platform manylinux_2_28_aarch64' <<< "${args}" || return 1
  grep -q -- '--only-binary=:all:' <<< "${args}" || return 1
  grep -q -- '--require-hashes' <<< "${args}" || return 1
  ! grep -qi 'x86_64' <<< "${args}" || return 1
  unzip -Z1 "${ws}/out/tickets.zip" | grep -qx 'fakedep/__init__.py' || return 1
}

case_x86_binary_rejected() {
  local ws
  ws="$(new_workspace)"
  new_python_service "${ws}" tickets <<< '# no dependency' || return 1
  make_elf "${ws}/services/tickets/native.so" "${elf_x86_64}"
  ! run_package "${ws}" tickets || return 1
  grep -q 'non-arm64 binaries' "${ws}/stderr" || return 1
  [ ! -e "${ws}/out/tickets.zip" ] || return 1
}

case_aarch64_binary_accepted() {
  local ws
  ws="$(new_workspace)"
  new_python_service "${ws}" tickets <<< '# no dependency' || return 1
  make_elf "${ws}/services/tickets/native.so" "${elf_aarch64}"
  run_package "${ws}" tickets || return 1
  unzip -Z1 "${ws}/out/tickets.zip" | grep -qx 'native.so' || return 1
}

# Requirements that must be refused before pip runs (supply chain). Reads the requirements from stdin.
refused_requirements() {
  local ws message="$1"
  ws="$(new_workspace)"
  new_python_service "${ws}" tickets || return 1
  ! run_package "${ws}" tickets || return 1
  grep -q "${message}" "${ws}/stderr" || return 1
  # Refused before any install: the stub was never called.
  [ ! -s "${ws}/pip.log" ] || return 1
  [ ! -e "${ws}/out/tickets.zip" ] || return 1
}

case_unpinned_requirement_rejected() {
  refused_requirements 'not pinned with ==' <<< 'requests>=2.0'
}

case_unhashed_requirement_rejected() {
  refused_requirements 'no sha256 hash' <<< 'requests==2.32.3'
}

case_malformed_hash_rejected() {
  refused_requirements 'malformed hash' <<< "requests==2.32.3 --hash=sha256:${hex_a} --hash=sha256:abc"
}

case_wrong_algorithm_rejected() {
  refused_requirements 'no sha256 hash' <<< "requests==2.32.3 --hash=sha512:${hex_a}"
}

case_option_line_rejected() {
  refused_requirements 'option line not allowed' << EOF
--index-url https://example.invalid/simple
requests==2.32.3 --hash=sha256:${hex_a}
EOF
}

case_unhashed_among_hashed_rejected() {
  refused_requirements 'no sha256 hash: urllib3' << EOF
requests==2.32.3 --hash=sha256:${hex_a}
urllib3==2.2.1
EOF
}

case_secret_file_refused() {
  local ws
  ws="$(new_workspace)"
  new_python_service "${ws}" tickets <<< '# no dependency' || return 1
  echo 'TOKEN=x' > "${ws}/services/tickets/.env"
  ! run_package "${ws}" tickets || return 1
  grep -q 'secret-looking files' "${ws}/stderr" || return 1
}

case_invalid_service_name_refused() {
  local ws
  ws="$(new_workspace)"
  ! run_package "${ws}" '../etc' || return 1
  ! run_package "${ws}" 'Tickets' || return 1
  grep -q 'invalid service name' "${ws}/stderr" || return 1
}

check 'EN-74-AC1 zip and sha256 file are produced and consistent' case_zip_and_checksum
check 'EN-74-AC1 outputs carry the base64 CodeSha256 of the zip' case_outputs_match_zip
check 'EN-74-AC1 same sources give the same zip (reproducible)' case_reproducible_zip
check 'EN-74-AC1 a source change changes the zip' case_content_change_changes_zip
check 'EN-74-AC1 pip is told to fetch aarch64 binary wheels with hashes' case_pip_targets_arm64_with_hashes
check 'EN-74-AC1 an x86-64 binary is refused' case_x86_binary_rejected
check 'EN-74-AC1 an aarch64 binary is accepted' case_aarch64_binary_accepted
check 'EN-74-SEC unpinned requirement is refused' case_unpinned_requirement_rejected
check 'EN-74-SEC requirement without hash is refused' case_unhashed_requirement_rejected
check 'EN-74-SEC malformed sha256 is refused' case_malformed_hash_rejected
check 'EN-74-SEC non-sha256 hash is refused' case_wrong_algorithm_rejected
check 'EN-74-SEC option lines (--index-url, -r, -e) are refused' case_option_line_rejected
check 'EN-74-SEC one unhashed line among hashed ones is refused' case_unhashed_among_hashed_rejected
check 'EN-74-SEC secret-looking files are refused' case_secret_file_refused
check 'EN-74-SEC invalid service names are refused' case_invalid_service_name_refused

printf '\n%s/%s package cases passed\n' "$((total - failures))" "${total}"
[ "${failures}" = 0 ]
