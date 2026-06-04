using '../main.bicep'

param environment = 'prod'
param workload = 'devsecops'
param location = 'southeastasia'
param locationShort = 'sea'

param tags = {
  owner: 'ReVerse'
  dataClassification: 'lab'
  costCenter: 'portfolio'
}

param vnetAddressPrefixes = [
  '10.20.0.0/16'
]
param appSubnetPrefix = '10.20.1.0/24'
param managementSubnetPrefix = '10.20.10.0/24'
param privateEndpointSubnetPrefix = '10.20.20.0/24'
param appAllowedInboundPorts = [
  '443'
]

param logRetentionInDays = 90
param logDailyQuotaGb = 5
param logPublicNetworkAccessForIngestion = 'Enabled'
param logPublicNetworkAccessForQuery = 'Enabled'

// Flip this to true only after Graph permissions and break-glass exclusions are ready.
param deployConditionalAccessPolicies = false
param conditionalAccessPolicyState = 'enabledForReportingButNotEnforced'
param breakGlassUserObjectIds = []

// Flip this to true only when you are ready to enable paid Defender Standard plans.
param enableDefenderPlans = false
param enableDefenderAutoProvisioning = false
param defenderPlans = [
  {
    name: 'CloudPosture'
    pricingTier: 'Standard'
    subPlan: ''
    extensions: [
      {
        name: 'SensitiveDataDiscovery'
        isEnabled: 'True'
      }
    ]
  }
  {
    name: 'VirtualMachines'
    pricingTier: 'Standard'
    subPlan: 'P2'
    extensions: [
      {
        name: 'AgentlessVmScanning'
        isEnabled: 'True'
      }
    ]
  }
  {
    name: 'Containers'
    pricingTier: 'Standard'
    subPlan: ''
    extensions: [
      {
        name: 'ContainerSensor'
        isEnabled: 'True'
      }
      {
        name: 'ContainerRegistriesVulnerabilityAssessments'
        isEnabled: 'True'
      }
    ]
  }
  {
    name: 'KeyVaults'
    pricingTier: 'Standard'
    subPlan: ''
    extensions: []
  }
  {
    name: 'StorageAccounts'
    pricingTier: 'Standard'
    subPlan: 'DefenderForStorageV2'
    extensions: [
      {
        name: 'OnUploadMalwareScanning'
        isEnabled: 'True'
      }
      {
        name: 'SensitiveDataDiscovery'
        isEnabled: 'True'
      }
    ]
  }
]
