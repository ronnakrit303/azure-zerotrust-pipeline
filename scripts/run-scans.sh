#!/usr/bin/env bash
# Run local validation and security scans that mirror the CI security gates.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"

cd "${REPO_ROOT}"

SKIP_BICEP=false
SKIP_DOCKER=false
SKIP_CHECKOV=false
REQUIRE_CHECKOV=false
GENERATE_SARIF=false
FAIL_FAST=true
ARTIFACT_DIR="${ARTIFACT_DIR:-reports/scans/$(date -u +%Y%m%dT%H%M%SZ)}"
TMP_DIR="${TMPDIR:-/tmp}/azzt-scans-$$"
FAILURES=0

mkdir -p "${TMP_DIR}"
trap 'rm -rf "${TMP_DIR}"' EXIT

usage() {
  cat <<'EOF'
Usage: scripts/run-scans.sh [options]

Runs local quality and security checks for the Azure Zero Trust lab.
Required gates fail the script. Optional tools such as Docker and Checkov are
skipped with a warning unless explicitly required.

Options:
      --skip-bicep       Skip az bicep build/build-params checks
      --skip-docker      Skip local Docker build and Trivy image scan
      --skip-checkov     Skip Checkov even when installed
      --require-checkov  Fail if Checkov is not installed
      --sarif            Write SARIF scanner output under reports/scans/
      --no-fail-fast     Continue after failures and report all failed steps
  -h, --help             Show this help

Examples:
  scripts/run-scans.sh
  scripts/run-scans.sh --skip-docker
  scripts/run-scans.sh --sarif --no-fail-fast
EOF
}

log() {
  printf '\n==> %s\n' "$*"
}

ok() {
  printf 'OK: %s\n' "$*"
}

warn() {
  printf 'WARN: %s\n' "$*" >&2
}

fail() {
  printf 'FAIL: %s\n' "$*" >&2
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

require_cmd() {
  has_cmd "$1" || {
    fail "Required command not found: $1"
    return 1
  }
}

run_step() {
  local name="$1"
  shift

  log "${name}"
  set +e
  "$@"
  local status=$?
  set -e

  if [[ ${status} -eq 0 ]]; then
    ok "${name}"
    return 0
  fi

  fail "${name} exited with code ${status}"
  FAILURES=$((FAILURES + 1))
  if [[ "${FAIL_FAST}" == "true" ]]; then
    exit "${status}"
  fi
  return 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-bicep)
      SKIP_BICEP=true
      shift
      ;;
    --skip-docker)
      SKIP_DOCKER=true
      shift
      ;;
    --skip-checkov)
      SKIP_CHECKOV=true
      shift
      ;;
    --require-checkov)
      REQUIRE_CHECKOV=true
      shift
      ;;
    --sarif)
      GENERATE_SARIF=true
      shift
      ;;
    --no-fail-fast)
      FAIL_FAST=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown option: $1"
      usage
      exit 2
      ;;
  esac
done

if [[ "${GENERATE_SARIF}" == "true" ]]; then
  mkdir -p "${ARTIFACT_DIR}"
fi

json_parse_check() {
  require_cmd python || return 1
  python -X utf8 - <<'PY'
import json
import pathlib
import sys

skip_parts = {'.git', '.venv', 'venv', 'node_modules', 'reports', '__pycache__'}
files = [
    path for path in pathlib.Path('.').rglob('*.json')
    if not any(part in skip_parts for part in path.parts)
]

for path in files:
    with path.open(encoding='utf-8') as handle:
        json.load(handle)

print(f'json ok: {len(files)} files')
PY
}

yaml_parse_check() {
  require_cmd python || return 1
  python -X utf8 - <<'PY'
import pathlib
import sys

try:
    import yaml
except ModuleNotFoundError:
    print('WARN: PyYAML is not installed; skipping YAML parse')
    raise SystemExit(0)

skip_parts = {'.git', '.venv', 'venv', 'node_modules', 'reports', '__pycache__'}
files = [
    path for pattern in ('*.yml', '*.yaml')
    for path in pathlib.Path('.').rglob(pattern)
    if not any(part in skip_parts for part in path.parts)
]

for path in files:
    yaml.safe_load(path.read_text(encoding='utf-8'))

print(f'yaml ok: {len(files)} files')
PY
}

kql_contract_check() {
  require_cmd python || return 1
  python -X utf8 - <<'PY'
import pathlib
import sys

required_tokens = ['TimeGenerated', 'AccountName', 'IPAddress', 'Action', 'Severity']
failed = False

for path in sorted(pathlib.Path('sentinel/detection-rules').glob('*.kql')):
    text = path.read_text(encoding='utf-8')
    first_line = text.splitlines()[0] if text.splitlines() else ''
    missing = [token for token in required_tokens if token not in text]
    if not first_line.startswith('// Tactic:') or 'Technique:' not in first_line:
        print(f'{path}: missing MITRE comment header')
        failed = True
    if missing:
        print(f'{path}: missing projected fields: {", ".join(missing)}')
        failed = True

if failed:
    raise SystemExit(1)

print('kql ok')
PY
}

app_tests() {
  require_cmd python || return 1
  python -X utf8 -m unittest discover -s app/tests -v
}

python_compile_check() {
  require_cmd python || return 1
  python -X utf8 -m compileall app/src app/tests
}

bicep_checks() {
  require_cmd az || return 1

  az bicep build --file infra/main.bicep --outfile "${TMP_DIR}/infra-main.json"
  az bicep build --file policy/main.bicep --outfile "${TMP_DIR}/policy-main.json"
  az bicep build-params --file infra/parameters/dev.bicepparam --stdout > "${TMP_DIR}/infra-dev.parameters.json"
  az bicep build-params --file infra/parameters/prod.bicepparam --stdout > "${TMP_DIR}/infra-prod.parameters.json"
  az bicep build-params --file policy/parameters/dev.bicepparam --stdout > "${TMP_DIR}/policy-dev.parameters.json"
  az bicep build-params --file policy/parameters/prod.bicepparam --stdout > "${TMP_DIR}/policy-prod.parameters.json"
}

gitleaks_scan() {
  require_cmd gitleaks || return 1
  gitleaks detect --source . --config .gitleaks.toml --no-git --redact --verbose
}

semgrep_scan() {
  require_cmd semgrep || return 1

  if [[ "${GENERATE_SARIF}" == "true" ]]; then
    semgrep scan \
      --config p/owasp-top-ten \
      --config p/secrets \
      --error \
      --metrics=off \
      --sarif \
      --output "${ARTIFACT_DIR}/semgrep.sarif" \
      .
  else
    semgrep scan \
      --config p/owasp-top-ten \
      --config p/secrets \
      --error \
      --metrics=off \
      .
  fi
}

trivy_fs_scan() {
  require_cmd trivy || return 1
  trivy fs \
    --config trivy.yaml \
    --scanners vuln,secret,misconfig \
    --severity CRITICAL \
    --exit-code 1 \
    app
}

checkov_scan() {
  if [[ "${SKIP_CHECKOV}" == "true" ]]; then
    warn "Checkov skipped by --skip-checkov"
    return 0
  fi

  if ! has_cmd checkov; then
    if [[ "${REQUIRE_CHECKOV}" == "true" ]]; then
      fail "Checkov is required but not installed"
      return 1
    fi
    warn "Checkov is not installed; skipping local IaC scan. CI installs Checkov automatically."
    return 0
  fi

  if [[ "${GENERATE_SARIF}" == "true" ]]; then
    checkov \
      --directory infra \
      --framework bicep \
      --output cli \
      --output sarif \
      --output-file-path console,"${ARTIFACT_DIR}/checkov.sarif" \
      --soft-fail
  else
    checkov --directory infra --framework bicep --quiet --soft-fail
  fi
}

docker_image_scan() {
  if [[ "${SKIP_DOCKER}" == "true" ]]; then
    warn "Docker image scan skipped by --skip-docker"
    return 0
  fi

  if ! has_cmd docker; then
    warn "Docker is not installed; skipping image build and scan"
    return 0
  fi

  if ! docker info >/dev/null 2>&1; then
    warn "Docker engine is not running; skipping image build and scan"
    return 0
  fi

  require_cmd trivy || return 1

  local image_tag="azure-zerotrust-demo:local"
  docker build --pull --tag "${image_tag}" app
  trivy image \
    --config trivy.yaml \
    --severity CRITICAL \
    --exit-code 1 \
    "${image_tag}"
}

powershell_parse_check() {
  local ps_command='$tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile("scripts/export-compliance.ps1", [ref]$tokens, [ref]$errors) > $null; if ($errors.Count -gt 0) { $errors | Format-List | Out-String | Write-Error; exit 1 }'

  if has_cmd pwsh; then
    pwsh -NoProfile -NonInteractive -Command "${ps_command}"
  elif has_cmd powershell.exe; then
    powershell.exe -NoProfile -NonInteractive -Command "${ps_command}"
  else
    warn "PowerShell is not installed; skipping export-compliance.ps1 parser check"
    return 0
  fi
}

run_step "Git whitespace check" git diff --check
run_step "JSON parse check" json_parse_check
run_step "YAML parse check" yaml_parse_check
run_step "KQL detection contract check" kql_contract_check
run_step "Python unit tests" app_tests
run_step "Python compile check" python_compile_check
run_step "PowerShell script parser check" powershell_parse_check

if [[ "${SKIP_BICEP}" == "true" ]]; then
  warn "Bicep checks skipped by --skip-bicep"
else
  run_step "Bicep build and parameter checks" bicep_checks
fi

run_step "Secrets scan / Gitleaks" gitleaks_scan
run_step "SAST / Semgrep" semgrep_scan
run_step "Trivy filesystem scan" trivy_fs_scan
run_step "IaC / Checkov" checkov_scan
run_step "Docker image build and Trivy image scan" docker_image_scan

if [[ "${FAILURES}" -gt 0 ]]; then
  fail "${FAILURES} step(s) failed"
  exit 1
fi

log "All local scans passed"
if [[ "${GENERATE_SARIF}" == "true" ]]; then
  printf 'Scanner artifacts: %s\n' "${ARTIFACT_DIR}"
fi
