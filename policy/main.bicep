targetScope = 'subscription'

@description('Deployment environment name.')
@allowed([
  'dev'
  'prod'
])
param environment string

@description('Workload name used in Azure Policy resource names and default tag values.')
param workload string = 'devsecops'

@description('Azure region used for the policy assignment managed identity.')
param location string = 'southeastasia'

@description('Short Azure region code used in policy resource names.')
param locationShort string = 'sea'

@description('Policy assignment enforcement mode. Use DoNotEnforce while validating audit results.')
@allowed([
  'Default'
  'DoNotEnforce'
])
param enforcementMode string = 'DoNotEnforce'

@description('Policy effect for public IP address resources.')
@allowed([
  'audit'
  'deny'
  'disabled'
])
param publicIpEffect string = 'audit'

@description('Policy effect for HTTPS requirements.')
@allowed([
  'audit'
  'deny'
  'disabled'
])
param httpsEffect string = 'audit'

@description('Policy effect for required tags. Use audit first, then modify for enforcement and remediation.')
@allowed([
  'audit'
  'modify'
  'disabled'
])
param tagEffect string = 'audit'

@description('Required tags to enforce. Each item must contain name and value properties.')
param requiredTags array = [
  {
    name: 'project'
    value: 'azure-zerotrust-pipeline'
  }
  {
    name: 'workload'
    value: workload
  }
  {
    name: 'environment'
    value: environment
  }
  {
    name: 'managedBy'
    value: 'azure-policy'
  }
]

@description('Optional scopes to exclude from the baseline assignment.')
param notScopes array = []

@description('Set true to create remediation tasks for tag modify policy references.')
param createRemediationTasks bool = false

@description('Maximum resources each remediation task should remediate.')
@minValue(1)
param remediationResourceCount int = 500

@description('Maximum parallel deployments for each remediation task.')
@minValue(1)
param remediationParallelDeployments int = 10

@description('Optional remediation location filters. Empty means all locations.')
param remediationLocations array = []

var namingSuffix = '${environment}-${locationShort}'
var denyPublicIpPolicyName = 'azzt-deny-public-ip-${namingSuffix}'
var requireHttpsPolicyName = 'azzt-require-https-${namingSuffix}'
var enforceTagsPolicyName = 'azzt-enforce-tags-${namingSuffix}'
var initiativeName = 'azzt-cis-${namingSuffix}'
var policyAssignmentName = 'azzt-cis-${namingSuffix}'
var tagContributorRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4a9ae827-6dc8-4573-8ac7-8239d42aa03f')

var denyPublicIpDefinition = loadJsonContent('./definitions/deny-public-ip.json')
var requireHttpsDefinition = loadJsonContent('./definitions/require-https.json')
var enforceTagsDefinition = loadJsonContent('./definitions/enforce-tags.json')

var tagPolicyReferences = [
  for (requiredTag, index) in requiredTags: {
    policyDefinitionReferenceId: 'enforce-tag-${index + 1}'
    policyDefinitionId: enforceTagsPolicy.id
    groupNames: [
      'governance'
    ]
    parameters: {
      tagName: {
        value: requiredTag.name
      }
      tagValue: {
        value: requiredTag.value
      }
      effect: {
        value: tagEffect
      }
    }
  }
]

var baseNonComplianceMessages = [
  {
    policyDefinitionReferenceId: 'deny-public-ip'
    message: 'Public IP address resources are not allowed for this Zero Trust baseline.'
  }
  {
    policyDefinitionReferenceId: 'require-https'
    message: 'Supported services must require HTTPS-only access.'
  }
]

var tagNonComplianceMessages = [
  for (requiredTag, index) in requiredTags: {
    policyDefinitionReferenceId: 'enforce-tag-${index + 1}'
    message: 'Resource must include tag ${requiredTag.name} with the approved value.'
  }
]

var baselineNonComplianceMessages = concat(baseNonComplianceMessages, tagNonComplianceMessages)

@description('Custom Azure Policy definition that audits or denies public IP address resources.')
resource denyPublicIpPolicy 'Microsoft.Authorization/policyDefinitions@2021-06-01' = {
  name: denyPublicIpPolicyName
  properties: denyPublicIpDefinition.properties
}

@description('Custom Azure Policy definition that requires HTTPS-only settings for supported services.')
resource requireHttpsPolicy 'Microsoft.Authorization/policyDefinitions@2021-06-01' = {
  name: requireHttpsPolicyName
  properties: requireHttpsDefinition.properties
}

@description('Custom Azure Policy definition that enforces required tags with modify remediation.')
resource enforceTagsPolicy 'Microsoft.Authorization/policyDefinitions@2021-06-01' = {
  name: enforceTagsPolicyName
  properties: enforceTagsDefinition.properties
}

@description('Custom CIS-aligned Zero Trust initiative that groups network, transport, and governance policies.')
resource cisBaselineInitiative 'Microsoft.Authorization/policySetDefinitions@2021-06-01' = {
  name: initiativeName
  properties: {
    displayName: 'AZZT - CIS Azure Benchmark Zero Trust baseline (${environment})'
    description: 'Custom initiative for the azure-zerotrust-pipeline lab. Start with audit effects, then enforce public IP, HTTPS, and tag governance controls.'
    policyType: 'Custom'
    metadata: {
      version: '1.0.0'
      category: 'Security'
      source: 'azure-zerotrust-pipeline'
      environment: environment
      cisBenchmark: 'CIS Microsoft Azure Foundations Benchmark v2.0.0'
    }
    policyDefinitionGroups: [
      {
        name: 'network'
        displayName: 'Network exposure'
        category: 'Security'
        description: 'Policies that reduce public network exposure.'
      }
      {
        name: 'transport'
        displayName: 'Transport security'
        category: 'Security'
        description: 'Policies that require HTTPS-only service access.'
      }
      {
        name: 'governance'
        displayName: 'Governance'
        category: 'Governance'
        description: 'Policies that enforce required resource metadata.'
      }
    ]
    policyDefinitions: concat([
      {
        policyDefinitionReferenceId: 'deny-public-ip'
        policyDefinitionId: denyPublicIpPolicy.id
        groupNames: [
          'network'
        ]
        parameters: {
          effect: {
            value: publicIpEffect
          }
        }
      }
      {
        policyDefinitionReferenceId: 'require-https'
        policyDefinitionId: requireHttpsPolicy.id
        groupNames: [
          'transport'
        ]
        parameters: {
          effect: {
            value: httpsEffect
          }
        }
      }
    ], tagPolicyReferences)
  }
}

@description('Subscription-scope Azure Policy assignment for the custom Zero Trust baseline initiative.')
resource cisBaselineAssignment 'Microsoft.Authorization/policyAssignments@2022-06-01' = {
  name: policyAssignmentName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: 'AZZT - CIS Azure Benchmark Zero Trust baseline (${environment})'
    description: 'Assigns the custom Zero Trust policy initiative at subscription scope.'
    enforcementMode: enforcementMode
    policyDefinitionId: cisBaselineInitiative.id
    notScopes: notScopes
    metadata: {
      version: '1.0.0'
      category: 'Security'
      assignedBy: 'Bicep'
      environment: environment
      workload: workload
    }
    nonComplianceMessages: baselineNonComplianceMessages
  }
}

@description('Least-privilege role assignment that lets the policy assignment managed identity remediate tags.')
resource assignmentTagContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (tagEffect == 'modify') {
  name: guid(subscription().id, policyAssignmentName, tagContributorRoleDefinitionId)
  properties: {
    roleDefinitionId: tagContributorRoleDefinitionId
    principalId: cisBaselineAssignment.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

@description('Azure Policy remediation tasks for existing resources missing required tags.')
resource tagRemediations 'Microsoft.PolicyInsights/remediations@2021-10-01' = [for (requiredTag, index) in requiredTags: if (createRemediationTasks && tagEffect == 'modify') {
  name: 'remediate-${policyAssignmentName}-tag-${index + 1}'
  dependsOn: [
    assignmentTagContributor
  ]
  properties: {
    policyAssignmentId: cisBaselineAssignment.id
    policyDefinitionReferenceId: 'enforce-tag-${index + 1}'
    resourceDiscoveryMode: 'ReEvaluateCompliance'
    resourceCount: remediationResourceCount
    parallelDeployments: remediationParallelDeployments
    filters: {
      locations: remediationLocations
    }
  }
}]

@description('Custom initiative resource ID.')
output initiativeResourceId string = cisBaselineInitiative.id

@description('Policy assignment resource ID.')
output policyAssignmentResourceId string = cisBaselineAssignment.id

@description('Policy assignment managed identity principal ID.')
output policyAssignmentPrincipalId string = cisBaselineAssignment.identity.principalId

@description('Required tag policy reference IDs used for remediation.')
output tagPolicyDefinitionReferenceIds array = [
  for (requiredTag, index) in requiredTags: 'enforce-tag-${index + 1}'
]
