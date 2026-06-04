using '../main.bicep'

param environment = 'dev'
param workload = 'devsecops'
param location = 'southeastasia'
param locationShort = 'sea'

param tags = {
  owner: 'ReVerse'
  dataClassification: 'lab'
  costCenter: 'portfolio'
}

param vnetAddressPrefixes = [
  '10.10.0.0/16'
]
param appSubnetPrefix = '10.10.1.0/24'
param managementSubnetPrefix = '10.10.10.0/24'
param privateEndpointSubnetPrefix = '10.10.20.0/24'
param appAllowedInboundPorts = [
  '443'
]

param logRetentionInDays = 30
param logDailyQuotaGb = 1
param logPublicNetworkAccessForIngestion = 'Enabled'
param logPublicNetworkAccessForQuery = 'Enabled'

// Keep disabled until the managed identity has Microsoft Graph Conditional Access permissions
// and breakGlassUserObjectIds contains at least one emergency access account object ID.
param deployConditionalAccessPolicies = false
param conditionalAccessPolicyState = 'enabledForReportingButNotEnforced'
param breakGlassUserObjectIds = []

// Keep disabled by default because Defender Standard plans can incur cost.
param enableDefenderPlans = false
param enableDefenderAutoProvisioning = false
param defenderPlans = [
  {
    name: 'CloudPosture'
    pricingTier: 'Free'
    subPlan: ''
    extensions: []
  }
  {
    name: 'KeyVaults'
    pricingTier: 'Free'
    subPlan: ''
    extensions: []
  }
]
