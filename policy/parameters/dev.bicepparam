using '../main.bicep'

param environment = 'dev'
param workload = 'devsecops'
param location = 'southeastasia'
param locationShort = 'sea'
param enforcementMode = 'DoNotEnforce'
param publicIpEffect = 'audit'
param httpsEffect = 'audit'
param tagEffect = 'audit'
param createRemediationTasks = false
param requiredTags = [
  {
    name: 'project'
    value: 'azure-zerotrust-pipeline'
  }
  {
    name: 'workload'
    value: 'devsecops'
  }
  {
    name: 'environment'
    value: 'dev'
  }
  {
    name: 'managedBy'
    value: 'azure-policy'
  }
]
