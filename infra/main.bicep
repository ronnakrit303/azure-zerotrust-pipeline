targetScope = 'subscription'

@description('Deployment environment name.')
@allowed([
  'dev'
  'prod'
])
param environment string

@description('Workload name used in Azure resource names.')
param workload string = 'devsecops'

@description('Azure region for resource group scoped resources.')
param location string = 'southeastasia'

@description('Short Azure region code used in resource names.')
param locationShort string = 'sea'

@description('Optional resource group name. Leave empty to use Microsoft naming convention.')
param resourceGroupName string = ''

@description('Tags applied to all resources that support tags.')
param tags object = {}

@description('Virtual network address prefixes.')
param vnetAddressPrefixes array

@description('Application subnet CIDR.')
param appSubnetPrefix string

@description('Management subnet CIDR.')
param managementSubnetPrefix string

@description('Private endpoint subnet CIDR.')
param privateEndpointSubnetPrefix string

@description('Allowed inbound TCP ports from the management subnet to the application subnet.')
param appAllowedInboundPorts array = [
  '443'
]

@description('Log Analytics workspace retention in days.')
@minValue(30)
param logRetentionInDays int = 30

@description('Log Analytics daily ingestion cap in GB. Use -1 for unlimited.')
param logDailyQuotaGb int = -1

@description('Public network access setting for Log Analytics ingestion.')
@allowed([
  'Enabled'
  'Disabled'
])
param logPublicNetworkAccessForIngestion string = 'Enabled'

@description('Public network access setting for Log Analytics query.')
@allowed([
  'Enabled'
  'Disabled'
])
param logPublicNetworkAccessForQuery string = 'Enabled'

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

@description('Set true to configure Microsoft Defender for Cloud pricing plans. This can create paid services.')
param enableDefenderPlans bool = false

@description('Microsoft Defender for Cloud plans to configure when enableDefenderPlans is true.')
param defenderPlans array = []

@description('Set true to enable Microsoft Defender for Cloud auto provisioning.')
param enableDefenderAutoProvisioning bool = false

var effectiveResourceGroupName = empty(resourceGroupName) ? 'rg-${workload}-${environment}-${locationShort}' : resourceGroupName
var commonTags = union({
  project: 'azure-zerotrust-pipeline'
  workload: workload
  environment: environment
  managedBy: 'bicep'
}, tags)

@description('Resource group that contains the lab workload resources.')
resource workloadResourceGroup 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: effectiveResourceGroupName
  location: location
  tags: commonTags
}

@description('Network module for VNet, subnets, and NSG microsegmentation.')
module network './modules/network.bicep' = {
  name: 'network-${environment}'
  scope: workloadResourceGroup
  params: {
    location: location
    environment: environment
    workload: workload
    locationShort: locationShort
    tags: commonTags
    vnetAddressPrefixes: vnetAddressPrefixes
    appSubnetPrefix: appSubnetPrefix
    managementSubnetPrefix: managementSubnetPrefix
    privateEndpointSubnetPrefix: privateEndpointSubnetPrefix
    appAllowedInboundPorts: appAllowedInboundPorts
  }
}

@description('Sentinel module for Log Analytics workspace and Microsoft Sentinel onboarding.')
module sentinel './modules/sentinel.bicep' = {
  name: 'sentinel-${environment}'
  scope: workloadResourceGroup
  params: {
    location: location
    environment: environment
    workload: workload
    locationShort: locationShort
    tags: commonTags
    retentionInDays: logRetentionInDays
    dailyQuotaGb: logDailyQuotaGb
    publicNetworkAccessForIngestion: logPublicNetworkAccessForIngestion
    publicNetworkAccessForQuery: logPublicNetworkAccessForQuery
  }
}

@description('Identity module for Entra Conditional Access deployment automation.')
module identity './modules/identity.bicep' = {
  name: 'identity-${environment}'
  scope: workloadResourceGroup
  params: {
    location: location
    environment: environment
    workload: workload
    locationShort: locationShort
    tags: commonTags
    deployConditionalAccessPolicies: deployConditionalAccessPolicies
    conditionalAccessPolicyState: conditionalAccessPolicyState
    breakGlassUserObjectIds: breakGlassUserObjectIds
  }
}

@description('Defender module for Microsoft Defender for Cloud subscription settings.')
module defender './modules/defender.bicep' = {
  name: 'defender-${environment}'
  params: {
    enableDefenderPlans: enableDefenderPlans
    defenderPlans: defenderPlans
    enableAutoProvisioning: enableDefenderAutoProvisioning
  }
}

@description('Resource group name for the deployment.')
output resourceGroupName string = workloadResourceGroup.name

@description('Virtual network resource ID.')
output vnetResourceId string = network.outputs.vnetResourceId

@description('Log Analytics workspace resource ID.')
output logAnalyticsWorkspaceResourceId string = sentinel.outputs.workspaceResourceId

@description('Microsoft Sentinel onboarding state resource ID.')
output sentinelOnboardingStateResourceId string = sentinel.outputs.sentinelOnboardingStateResourceId

@description('Conditional Access deployment managed identity principal ID. Empty when disabled.')
output conditionalAccessManagedIdentityPrincipalId string = identity.outputs.conditionalAccessManagedIdentityPrincipalId

@description('Configured Microsoft Defender plan names. Empty when disabled.')
output defenderConfiguredPlanNames array = defender.outputs.configuredPlanNames
