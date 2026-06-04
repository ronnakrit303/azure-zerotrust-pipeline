targetScope = 'resourceGroup'

@description('Azure region for Log Analytics and Sentinel resources.')
param location string

@description('Deployment environment name.')
param environment string

@description('Workload name used in Azure resource names.')
param workload string

@description('Short Azure region code used in resource names.')
param locationShort string

@description('Tags applied to monitoring resources.')
param tags object

@description('Optional Log Analytics workspace name. Leave empty to use Microsoft naming convention.')
param workspaceName string = ''

@description('Log Analytics workspace retention in days.')
@minValue(30)
param retentionInDays int = 30

@description('Log Analytics daily ingestion cap in GB. Use -1 for unlimited.')
param dailyQuotaGb int = -1

@description('Public network access setting for Log Analytics ingestion.')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccessForIngestion string = 'Enabled'

@description('Public network access setting for Log Analytics query.')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccessForQuery string = 'Enabled'

var effectiveWorkspaceName = empty(workspaceName) ? 'log-${workload}-${environment}-${locationShort}' : workspaceName

@description('Log Analytics workspace used by Microsoft Sentinel.')
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-07-01' = {
  name: effectiveWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    workspaceCapping: {
      dailyQuotaGb: dailyQuotaGb
    }
    publicNetworkAccessForIngestion: publicNetworkAccessForIngestion
    publicNetworkAccessForQuery: publicNetworkAccessForQuery
    features: {
      disableLocalAuth: true
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

@description('Microsoft Sentinel onboarding state for the Log Analytics workspace.')
resource sentinelOnboardingState 'Microsoft.SecurityInsights/onboardingStates@2023-02-01' = {
  scope: logAnalyticsWorkspace
  name: 'default'
  properties: {
    customerManagedKey: false
  }
}

@description('Log Analytics workspace name.')
output workspaceName string = logAnalyticsWorkspace.name

@description('Log Analytics workspace resource ID.')
output workspaceResourceId string = logAnalyticsWorkspace.id

@description('Log Analytics workspace customer ID.')
output workspaceCustomerId string = logAnalyticsWorkspace.properties.customerId

@description('Microsoft Sentinel onboarding state resource ID.')
output sentinelOnboardingStateResourceId string = sentinelOnboardingState.id
