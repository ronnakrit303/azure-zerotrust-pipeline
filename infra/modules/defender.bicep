targetScope = 'subscription'

@description('Set true to configure Microsoft Defender for Cloud pricing plans. This can create paid services.')
param enableDefenderPlans bool = false

@description('Microsoft Defender for Cloud plans to configure when enableDefenderPlans is true.')
param defenderPlans array = []

@description('Set true to enable Microsoft Defender for Cloud auto provisioning.')
param enableAutoProvisioning bool = false

var configuredPlanNames = [
  for plan in defenderPlans: plan.name
]

@description('Microsoft Defender for Cloud automatic provisioning setting.')
resource autoProvisioningSetting 'Microsoft.Security/autoProvisioningSettings@2017-08-01-preview' = if (enableAutoProvisioning) {
  name: 'default'
  properties: {
    autoProvision: 'On'
  }
}

@description('Microsoft Defender for Cloud pricing plans at subscription scope.')
resource defenderPricingPlans 'Microsoft.Security/pricings@2024-01-01' = [for plan in defenderPlans: if (enableDefenderPlans) {
  name: plan.name
  properties: union({
    pricingTier: plan.pricingTier
  }, empty(plan.subPlan) ? {} : {
    subPlan: plan.subPlan
  }, empty(plan.extensions) ? {} : {
    extensions: plan.extensions
  })
}]

@description('Configured Microsoft Defender plan names. Empty when disabled.')
output configuredPlanNames array = enableDefenderPlans ? configuredPlanNames : []

@description('Microsoft Defender auto provisioning enabled flag.')
output autoProvisioningEnabled bool = enableAutoProvisioning
