targetScope = 'resourceGroup'

@description('Azure region for deployment script resources.')
param location string

@description('Deployment environment name.')
param environment string

@description('Workload name used in Azure resource names.')
param workload string

@description('Short Azure region code used in resource names.')
param locationShort string

@description('Tags applied to identity automation resources.')
param tags object

@description('Set true to run the Conditional Access deployment script.')
param deployConditionalAccessPolicies bool = false

@description('Conditional Access policy state. Start with report-only before enforcing.')
@allowed([
  'disabled'
  'enabled'
  'enabledForReportingButNotEnforced'
])
param conditionalAccessPolicyState string = 'enabledForReportingButNotEnforced'

@description('Emergency access user object IDs excluded from Conditional Access policies.')
param breakGlassUserObjectIds array = []

@description('Optional managed identity name for the Conditional Access deployment script.')
param conditionalAccessScriptIdentityName string = ''

@description('Forces the deployment script to rerun when the value changes.')
param deploymentScriptForceUpdateTag string = utcNow('u')

var effectiveConditionalAccessIdentityName = empty(conditionalAccessScriptIdentityName) ? 'id-${workload}-ca-${environment}-${locationShort}' : conditionalAccessScriptIdentityName
var conditionalAccessDeploymentScriptName = 'ds-${workload}-ca-${environment}-${locationShort}'

@description('User-assigned identity used by the Conditional Access deployment script.')
resource conditionalAccessDeploymentIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = if (deployConditionalAccessPolicies) {
  name: effectiveConditionalAccessIdentityName
  location: location
  tags: tags
}

@description('Deployment script that creates or updates Microsoft Entra Conditional Access policies through Microsoft Graph.')
resource conditionalAccessPoliciesScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = if (deployConditionalAccessPolicies) {
  name: conditionalAccessDeploymentScriptName
  location: location
  tags: tags
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${conditionalAccessDeploymentIdentity.id}': {}
    }
  }
  properties: {
    azCliVersion: '2.61.0'
    cleanupPreference: 'OnSuccess'
    forceUpdateTag: deploymentScriptForceUpdateTag
    retentionInterval: 'P1D'
    timeout: 'PT30M'
    environmentVariables: [
      {
        name: 'BREAK_GLASS_USER_OBJECT_IDS'
        value: join(breakGlassUserObjectIds, ',')
      }
      {
        name: 'POLICY_STATE'
        value: conditionalAccessPolicyState
      }
      {
        name: 'MFA_POLICY_NAME'
        value: 'ZT - Require MFA for all users'
      }
      {
        name: 'LEGACY_AUTH_POLICY_NAME'
        value: 'ZT - Block legacy authentication'
      }
    ]
    scriptContent: '''
set -euo pipefail

if [ -z "${BREAK_GLASS_USER_OBJECT_IDS}" ]; then
  echo "At least one break-glass user object ID is required before deploying tenant-wide Conditional Access policies." >&2
  exit 1
fi

excluded_users_json=$(printf '%s' "${BREAK_GLASS_USER_OBJECT_IDS}" | jq -R 'split(",") | map(select(length > 0))')
excluded_users_count=$(printf '%s' "${excluded_users_json}" | jq 'length')

if [ "${excluded_users_count}" -eq 0 ]; then
  echo "No valid break-glass user object IDs were provided." >&2
  exit 1
fi

find_policy_id() {
  local display_name="$1"

  az rest \
    --method get \
    --url "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies" \
  | jq -r --arg displayName "${display_name}" '[.value[] | select(.displayName == $displayName) | .id][0] // ""'
}

upsert_policy() {
  local display_name="$1"
  local body_file="$2"
  local existing_id

  existing_id=$(find_policy_id "${display_name}")

  if [ -n "${existing_id}" ] && [ "${existing_id}" != "null" ]; then
    az rest \
      --method patch \
      --url "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies/${existing_id}" \
      --headers "Content-Type=application/json" \
      --body @"${body_file}" \
      >/dev/null
    echo "${existing_id}"
  else
    az rest \
      --method post \
      --url "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies" \
      --headers "Content-Type=application/json" \
      --body @"${body_file}" \
      --query id \
      -o tsv
  fi
}

mfa_policy_body=$(mktemp)
legacy_auth_policy_body=$(mktemp)

jq -n \
  --arg displayName "${MFA_POLICY_NAME}" \
  --arg state "${POLICY_STATE}" \
  --argjson excludeUsers "${excluded_users_json}" \
  '{
    displayName: $displayName,
    state: $state,
    conditions: {
      clientAppTypes: ["all"],
      applications: {
        includeApplications: ["All"]
      },
      users: {
        includeUsers: ["All"],
        excludeUsers: $excludeUsers
      }
    },
    grantControls: {
      operator: "OR",
      builtInControls: ["mfa"]
    }
  }' > "${mfa_policy_body}"

jq -n \
  --arg displayName "${LEGACY_AUTH_POLICY_NAME}" \
  --arg state "${POLICY_STATE}" \
  --argjson excludeUsers "${excluded_users_json}" \
  '{
    displayName: $displayName,
    state: $state,
    conditions: {
      clientAppTypes: [
        "exchangeActiveSync",
        "other"
      ],
      applications: {
        includeApplications: ["All"]
      },
      users: {
        includeUsers: ["All"],
        excludeUsers: $excludeUsers
      }
    },
    grantControls: {
      operator: "OR",
      builtInControls: ["block"]
    }
  }' > "${legacy_auth_policy_body}"

mfa_policy_id=$(upsert_policy "${MFA_POLICY_NAME}" "${mfa_policy_body}")
legacy_auth_policy_id=$(upsert_policy "${LEGACY_AUTH_POLICY_NAME}" "${legacy_auth_policy_body}")

jq -n \
  --arg mfaPolicyId "${mfa_policy_id}" \
  --arg legacyAuthPolicyId "${legacy_auth_policy_id}" \
  '{
    mfaPolicyId: $mfaPolicyId,
    legacyAuthPolicyId: $legacyAuthPolicyId
  }' > "${AZ_SCRIPTS_OUTPUT_PATH}"
'''
  }
}

@description('Conditional Access deployment enabled flag.')
output conditionalAccessDeploymentEnabled bool = deployConditionalAccessPolicies

@description('Conditional Access deployment managed identity name. Empty when disabled.')
output conditionalAccessManagedIdentityName string = deployConditionalAccessPolicies ? conditionalAccessDeploymentIdentity!.name : ''

@description('Conditional Access deployment managed identity resource ID. Empty when disabled.')
output conditionalAccessManagedIdentityResourceId string = deployConditionalAccessPolicies ? conditionalAccessDeploymentIdentity!.id : ''

@description('Conditional Access deployment managed identity principal ID. Empty when disabled.')
output conditionalAccessManagedIdentityPrincipalId string = deployConditionalAccessPolicies ? conditionalAccessDeploymentIdentity!.properties.principalId : ''
