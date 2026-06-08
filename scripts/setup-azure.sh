#!/usr/bin/env bash
# Prepare and validate Azure subscription-scope deployments for the lab.

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." >/dev/null 2>&1 && pwd)"

cd "${REPO_ROOT}"

ENVIRONMENT="${ENVIRONMENT:-dev}"
LOCATION="${LOCATION:-southeastasia}"
RUN_INFRA=true
RUN_POLICY=true
RUN_BICEP=true
RUN_VALIDATE=true
RUN_WHAT_IF=true
REGISTER_PROVIDERS=false

PROVIDERS=(
  "Microsoft.Resources"
  "Microsoft.Network"
  "Microsoft.OperationalInsights"
  "Microsoft.SecurityInsights"
  "Microsoft.ManagedIdentity"
  "Microsoft.Security"
  "Microsoft.Authorization"
  "Microsoft.PolicyInsights"
)

usage() {
  cat <<'EOF'
Usage: scripts/setup-azure.sh [options]

Validates the Bicep infrastructure and Azure Policy deployments for this lab.
It does not create resources. Use the printed az deployment commands after
reviewing validate and what-if output.

Options:
  -e, --environment <dev|prod>  Parameter set to use. Default: dev
  -l, --location <region>       Deployment metadata location. Default: southeastasia
      --infra-only              Validate only infra/main.bicep
      --policy-only             Validate only policy/main.bicep
      --skip-bicep              Skip local Bicep build/build-params checks
      --skip-validate           Skip az deployment sub validate
      --skip-what-if            Skip az deployment sub what-if
      --register-providers      Register required Azure resource providers
  -h, --help                    Show this help

Examples:
  scripts/setup-azure.sh --environment dev
  scripts/setup-azure.sh --environment prod --skip-what-if
  scripts/setup-azure.sh --environment dev --register-providers
EOF
}

log() {
  printf '\n==> %s\n' "$*"
}

warn() {
  printf 'WARN: %s\n' "$*" >&2
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -e|--environment)
      ENVIRONMENT="${2:-}"
      shift 2
      ;;
    -l|--location)
      LOCATION="${2:-}"
      shift 2
      ;;
    --infra-only)
      RUN_INFRA=true
      RUN_POLICY=false
      shift
      ;;
    --policy-only)
      RUN_INFRA=false
      RUN_POLICY=true
      shift
      ;;
    --skip-bicep)
      RUN_BICEP=false
      shift
      ;;
    --skip-validate)
      RUN_VALIDATE=false
      shift
      ;;
    --skip-what-if)
      RUN_WHAT_IF=false
      shift
      ;;
    --register-providers)
      REGISTER_PROVIDERS=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

[[ "${ENVIRONMENT}" == "dev" || "${ENVIRONMENT}" == "prod" ]] || die "Environment must be dev or prod."
[[ -n "${LOCATION}" ]] || die "Location cannot be empty."

INFRA_TEMPLATE="infra/main.bicep"
INFRA_PARAMS="infra/parameters/${ENVIRONMENT}.bicepparam"
POLICY_TEMPLATE="policy/main.bicep"
POLICY_PARAMS="policy/parameters/${ENVIRONMENT}.bicepparam"

[[ -f "${INFRA_TEMPLATE}" ]] || die "Missing ${INFRA_TEMPLATE}"
[[ -f "${POLICY_TEMPLATE}" ]] || die "Missing ${POLICY_TEMPLATE}"
[[ -f "${INFRA_PARAMS}" ]] || die "Missing ${INFRA_PARAMS}"
[[ -f "${POLICY_PARAMS}" ]] || die "Missing ${POLICY_PARAMS}"

TMP_DIR="${TMPDIR:-/tmp}/azzt-setup-$$"
mkdir -p "${TMP_DIR}"
trap 'rm -rf "${TMP_DIR}"' EXIT

need_cmd az

log "Checking Azure CLI login"
az account show --query "{subscription:name, tenant:tenantId, user:user.name}" -o table >/dev/null || {
  die "Azure CLI is not logged in. Run az login first."
}
az account show --query "{subscription:name, tenant:tenantId, user:user.name}" -o table

if [[ "${REGISTER_PROVIDERS}" == "true" ]]; then
  log "Registering Azure resource providers"
  for provider in "${PROVIDERS[@]}"; do
    printf 'Registering %s\n' "${provider}"
    az provider register --namespace "${provider}" >/dev/null
    az provider show --namespace "${provider}" --query "{namespace:namespace, state:registrationState}" -o table
  done
  warn "Provider registration can take several minutes to fully propagate."
else
  log "Provider registration check"
  for provider in "${PROVIDERS[@]}"; do
    az provider show --namespace "${provider}" --query "{namespace:namespace, state:registrationState}" -o table || {
      warn "Could not read provider state for ${provider}. Use --register-providers if needed."
    }
  done
fi

run_bicep_checks() {
  local name="$1"
  local template="$2"
  local params="$3"
  local artifact_prefix="$4"

  log "Building ${name} Bicep"
  az bicep build --file "${template}" --outfile "${TMP_DIR}/${artifact_prefix}.json"

  log "Building ${name} parameters"
  az bicep build-params --file "${params}" --stdout > "${TMP_DIR}/${artifact_prefix}.parameters.json"
}

run_validate() {
  local name="$1"
  local template="$2"
  local params="$3"

  log "Validating ${name} deployment"
  az deployment sub validate \
    --location "${LOCATION}" \
    --template-file "${template}" \
    --parameters "${params}"
}

run_what_if() {
  local name="$1"
  local template="$2"
  local params="$3"

  log "Running ${name} what-if"
  az deployment sub what-if \
    --location "${LOCATION}" \
    --template-file "${template}" \
    --parameters "${params}"
}

if [[ "${RUN_BICEP}" == "true" ]]; then
  log "Checking Bicep CLI"
  az bicep version

  if [[ "${RUN_INFRA}" == "true" ]]; then
    run_bicep_checks "infra" "${INFRA_TEMPLATE}" "${INFRA_PARAMS}" "infra-${ENVIRONMENT}"
  fi

  if [[ "${RUN_POLICY}" == "true" ]]; then
    run_bicep_checks "policy" "${POLICY_TEMPLATE}" "${POLICY_PARAMS}" "policy-${ENVIRONMENT}"
  fi
fi

if [[ "${RUN_VALIDATE}" == "true" ]]; then
  if [[ "${RUN_INFRA}" == "true" ]]; then
    run_validate "infra" "${INFRA_TEMPLATE}" "${INFRA_PARAMS}"
  fi

  if [[ "${RUN_POLICY}" == "true" ]]; then
    run_validate "policy" "${POLICY_TEMPLATE}" "${POLICY_PARAMS}"
  fi
fi

if [[ "${RUN_WHAT_IF}" == "true" ]]; then
  if [[ "${RUN_INFRA}" == "true" ]]; then
    run_what_if "infra" "${INFRA_TEMPLATE}" "${INFRA_PARAMS}"
  fi

  if [[ "${RUN_POLICY}" == "true" ]]; then
    run_what_if "policy" "${POLICY_TEMPLATE}" "${POLICY_PARAMS}"
  fi
fi

log "Setup validation complete"
cat <<EOF
Review the validate/what-if output above before deploying.

Infra deploy:
  az deployment sub create --name zt-infra-${ENVIRONMENT} --location ${LOCATION} --template-file ${INFRA_TEMPLATE} --parameters ${INFRA_PARAMS}

Policy deploy:
  az deployment sub create --name zt-policy-${ENVIRONMENT} --location ${LOCATION} --template-file ${POLICY_TEMPLATE} --parameters ${POLICY_PARAMS}
EOF
