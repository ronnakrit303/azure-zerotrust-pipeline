using '../main.bicep'

param environment = 'prod'
param workload = 'devsecops'
param location = 'southeastasia'
param locationShort = 'sea'
param enforcementMode = 'Default'
param publicIpEffect = 'deny'
param httpsEffect = 'deny'
param tagEffect = 'modify'
param createRemediationTasks = true
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
    value: 'prod'
  }
  {
    name: 'managedBy'
    value: 'azure-policy'
  }
]
