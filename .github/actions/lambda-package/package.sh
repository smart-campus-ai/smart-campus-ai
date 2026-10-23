#!/usr/bin/env bash
# Package services/<SERVICE> as a reproducible arm64 AWS Lambda zip.
#
# Inputs (environment): SERVICE, OUTPUT_DIR, PYTHON_VERSION, NODE_OUTPUT_DIR.
# Outputs ($GITHUB_OUTPUT): runtime, zip, sha256 (hex), code_sha256 (base64, the value Lambda reports as CodeSha256).
# Files written: <OUTPUT_DIR>/<SERVICE>.zip and <OUTPUT_DIR>/<SERVICE>.zip.sha256 (sha256sum format).
#
# Runtime detection (manifest at services/<SERVICE>/):
#   package.json     -> node   (pnpm-lock.yaml or package-lock.json required, frozen install, lifecycle scripts disabled)
#                       with a "build" script: the build must emit a self-contained bundle in NODE_OUTPUT_DIR (default dist/),
#                       whose content becomes the zip root; without one: sources + production node_modules.
#   requirements.txt -> python (binary wheels for manylinux aarch64 only, installed next to the sources;
#                       the file must be fully pinned and hash-locked, installed with pip --require-hashes)
#
# Reproducibility: fixed mtime and permissions, sorted entries, no extra attributes, UTC. The same inputs give the same
# zip, hence the same CodeSha256, which the deploy job uses to skip functions whose code did not change.
set -euo pipefail

export TZ=UTC LC_ALL=C

fail() {
  echo "lambda-package: $*" >&2
  exit 1
}

: "${SERVICE:?SERVICE is required}"
: "${OUTPUT_DIR:?OUTPUT_DIR is required}"
PYTHON_VERSION="${PYTHON_VERSION:-3.12}"
NODE_OUTPUT_DIR="${NODE_OUTPUT_DIR:-dist}"

re_service='^[a-z][a-z0-9-]{0,40}$'
re_python='^3\.[0-9]{1,2}$'
re_dir='^[A-Za-z0-9_][A-Za-z0-9_./-]*$'
[[ "${SERVICE}" =~ ${re_service} ]] || fail "invalid service name (expected ${re_service})"
[[ "${PYTHON_VERSION}" =~ ${re_python} ]] || fail "invalid python-version (expected ${re_python})"
if [[ ! "${NODE_OUTPUT_DIR}" =~ ${re_dir} || "${NODE_OUTPUT_DIR}" == *..* ]]; then
  fail "invalid node-output-dir (expected ${re_dir}, no '..')"
fi

src="services/${SERVICE}"
[ -d "${src}" ] || fail "${src} does not exist"

# Secret-looking files never ship: fail loudly instead of silently excluding them. node_modules is not scanned (fixtures).
forbidden="$(find "${src}" -name node_modules -prune -o -type f \( \
  -name '.env' -o \( -name '.env.*' ! -name '.env.example' \) -o -name '*.pem' -o -name '*.key' \
  -o -name '*.p12' -o -name '*.pfx' -o -name 'id_rsa*' -o -name '*.tfstate' \) -print)"
if [ -n "${forbidden}" ]; then
  printf '%s\n' "${forbidden}" >&2
  fail "secret-looking files found under ${src}, remove them"
fi

# Detect the runtime from the manifest.
has_node=0
has_python=0
if [ -f "${src}/package.json" ]; then has_node=1; fi
if [ -f "${src}/requirements.txt" ]; then has_python=1; fi
if [ "${has_node}" = 1 ] && [ "${has_python}" = 1 ]; then
  fail "${src} has both package.json and requirements.txt, keep one manifest"
elif [ "${has_node}" = 1 ]; then
  runtime=node
elif [ "${has_python}" = 1 ]; then
  runtime=python
elif [ -f "${src}/pyproject.toml" ]; then
  fail "${src} has pyproject.toml but no requirements.txt: export a pinned requirements.txt"
else
  fail "no package.json or requirements.txt in ${src}, cannot detect the runtime"
fi

work="$(mktemp -d)"
stage="$(mktemp -d)"
trap 'rm -rf "${work}" "${stage}"' EXIT

# Sources copied out of the workspace, without VCS data, dependencies and test files.
copy_sources() {
  tar -C "${src}" \
    --exclude=.git --exclude=node_modules --exclude=.venv --exclude=__pycache__ --exclude='*.pyc' \
    --exclude=.pytest_cache --exclude=coverage --exclude=tests --exclude=__tests__ \
    --exclude='*.test.*' --exclude='*.spec.*' \
    -cf - . | tar -C "$1" -xf -
}

package_node() {
  copy_sources "${work}"
  cd "${work}"

  # Native modules must resolve their linux/arm64 flavour (npm); the ELF check below enforces it for every package manager.
  export npm_config_os=linux npm_config_cpu=arm64 npm_config_libc=glibc

  local pm has_build=0
  if [ -f pnpm-lock.yaml ]; then
    pm=pnpm
  elif [ -f package-lock.json ]; then
    pm=npm
  else
    fail "${src} needs pnpm-lock.yaml or package-lock.json (frozen installs only)"
  fi
  if node -e 'const s = require("./package.json").scripts; process.exit(s && s.build ? 0 : 1)'; then
    has_build=1
  fi

  if [ "${has_build}" = 1 ]; then
    # Full install for the build; the bundle in NODE_OUTPUT_DIR must be self-contained.
    if [ "${pm}" = pnpm ]; then
      pnpm install --frozen-lockfile --ignore-scripts
    else
      npm ci --ignore-scripts --no-audit --no-fund
    fi
    "${pm}" run build
    [ -d "${NODE_OUTPUT_DIR}" ] || fail "the build did not produce ${NODE_OUTPUT_DIR}/ in ${src}"
    cp -a "${NODE_OUTPUT_DIR}/." "${stage}/"
  else
    # hoisted layout: no symlinks into a content-addressed store, the zip is self-contained.
    if [ "${pm}" = pnpm ]; then
      pnpm install --frozen-lockfile --ignore-scripts --prod --node-linker=hoisted
    else
      npm ci --ignore-scripts --omit=dev --no-audit --no-fund
    fi
    cp -a "${work}/." "${stage}/"
  fi
  cd - > /dev/null
}

# Fail unless every requirement is pinned (name==version) and carries at least one sha256 hash, with no option lines
# (-r, -e, --index-url...). Continuation lines are joined first. pip --require-hashes enforces the same at install time
# (including transitive dependencies); this check only gives an early, readable error.
check_hashed_requirements() {
  local file="$1" logical bad=0
  local re_pin='^[A-Za-z0-9][A-Za-z0-9._-]*(\[[A-Za-z0-9,._-]+\])?==[A-Za-z0-9._!+-]+([[:space:]]|;|$)'
  local re_hash='(^|[[:space:]])--hash=sha256:[0-9a-f]{64}([[:space:]]|$)'
  local re_any_hash='--hash=[^[:space:]]*'

  while IFS= read -r logical; do
    if [[ "${logical}" == -* ]]; then
      echo "option line not allowed: ${logical}" >&2
      bad=1
    elif [[ ! "${logical}" =~ ${re_pin} ]]; then
      echo "not pinned with ==: ${logical%% *}" >&2
      bad=1
    elif [[ ! "${logical}" =~ ${re_hash} ]]; then
      echo "no sha256 hash: ${logical%% *}" >&2
      bad=1
    else
      # Every --hash= must be a well-formed sha256 (a sha512 or truncated hash would pass the check above otherwise).
      local rest="${logical}" valid
      while [[ "${rest}" =~ ${re_any_hash} ]]; do
        valid="${BASH_REMATCH[0]}"
        [[ "${valid}" =~ ^--hash=sha256:[0-9a-f]{64}$ ]] || {
          echo "malformed hash for ${logical%% *}: ${valid}" >&2
          bad=1
          break
        }
        rest="${rest/"${valid}"/}"
      done
    fi
  done < <(awk '
    {
      line = $0
      sub(/[[:space:]]+#.*$/, "", line)
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      acc = (acc == "") ? line : acc " " line
      if (acc ~ /\\$/) { sub(/[[:space:]]*\\$/, "", acc); next }
      if (acc != "" && acc !~ /^#/) print acc
      acc = ""
    }
    END { if (acc != "" && acc !~ /^#/) print acc }
  ' "${file}")

  [ "${bad}" = 0 ] || fail "${file} must be fully pinned and hash-locked (pip-compile --generate-hashes, or uv export --format requirements-txt, includes transitive dependencies)"
}

package_python() {
  copy_sources "${stage}"
  # Only run pip when the file lists at least one requirement (comments and blank lines do not count).
  if grep -Eq '^[[:space:]]*[^#[:space:]]' "${src}/requirements.txt"; then
    check_hashed_requirements "${src}/requirements.txt"
    python -m pip install --no-cache-dir --no-compile --disable-pip-version-check \
      --require-hashes --only-binary=:all: --implementation cp --python-version "${PYTHON_VERSION}" \
      --platform manylinux2014_aarch64 --platform manylinux_2_28_aarch64 \
      --target "${stage}" --requirement "${src}/requirements.txt"
  fi
  find "${stage}" -name __pycache__ -prune -exec rm -rf {} +
}

case "${runtime}" in
  node) package_node ;;
  python) package_python ;;
esac

[ -n "$(ls -A "${stage}")" ] || fail "the package for ${SERVICE} is empty"

# Every native binary must be linux/arm64.
command -v file > /dev/null || fail "file(1) is required to verify the architecture"
bad=0
while IFS= read -r -d '' candidate; do
  info="$(file -b "${candidate}")"
  case "${info}" in
    ELF*aarch64*) ;;
    ELF*)
      echo "not aarch64: ${candidate#"${stage}"/} (${info})" >&2
      bad=1
      ;;
  esac
done < <(find "${stage}" -type f \( -name '*.node' -o -name '*.so' -o -name '*.so.*' -o -perm /111 \) -print0)
[ "${bad}" = 0 ] || fail "non-arm64 binaries found in the ${SERVICE} package"

# Normalise metadata, then zip in a stable order.
find "${stage}" -exec touch -h -d '2020-01-01 00:00:00 UTC' {} +
find "${stage}" -type d -exec chmod 755 {} +
find "${stage}" -type f -perm /111 -exec chmod 755 {} +
find "${stage}" -type f ! -perm /111 -exec chmod 644 {} +

mkdir -p "${OUTPUT_DIR}"
out_dir="$(cd "${OUTPUT_DIR}" && pwd)"
zip_path="${out_dir}/${SERVICE}.zip"
rm -f "${zip_path}"
(
  cd "${stage}"
  find . \( -type f -o -type l \) -print | cut -c3- | sort | zip -X -y -D -q -9 "${zip_path}" -@
)

sha256="$(sha256sum "${zip_path}" | cut -d' ' -f1)"
code_sha256="$(openssl dgst -sha256 -binary "${zip_path}" | base64 | tr -d '\n')"
printf '%s  %s\n' "${sha256}" "${SERVICE}.zip" > "${zip_path}.sha256"

size="$(wc -c < "${zip_path}" | tr -d ' ')"
echo "${SERVICE}: ${runtime}, ${size} bytes, sha256 ${sha256}"

{
  echo "runtime=${runtime}"
  echo "zip=${zip_path}"
  echo "sha256=${sha256}"
  echo "code_sha256=${code_sha256}"
} >> "${GITHUB_OUTPUT:-/dev/null}"
