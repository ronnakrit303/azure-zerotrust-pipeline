targetScope = 'resourceGroup'

@description('Azure region for network resources.')
param location string

@description('Deployment environment name.')
param environment string

@description('Workload name used in Azure resource names.')
param workload string

@description('Short Azure region code used in resource names.')
param locationShort string

@description('Tags applied to network resources.')
param tags object

@description('Optional virtual network name. Leave empty to use Microsoft naming convention.')
param vnetName string = ''

@description('Virtual network address prefixes.')
param vnetAddressPrefixes array

@description('Application subnet CIDR.')
param appSubnetPrefix string

@description('Management subnet CIDR.')
param managementSubnetPrefix string

@description('Private endpoint subnet CIDR.')
param privateEndpointSubnetPrefix string

@description('Allowed inbound TCP ports from management subnet to application subnet.')
param appAllowedInboundPorts array = [
  '443'
]

var effectiveVnetName = empty(vnetName) ? 'vnet-${workload}-${environment}-${locationShort}' : vnetName
var appSubnetName = 'snet-app'
var managementSubnetName = 'snet-mgmt'
var privateEndpointSubnetName = 'snet-pe'
var appNsgName = 'nsg-${workload}-app-${environment}-${locationShort}'
var managementNsgName = 'nsg-${workload}-mgmt-${environment}-${locationShort}'
var privateEndpointNsgName = 'nsg-${workload}-pe-${environment}-${locationShort}'
var appAllowInboundRules = [
  for (port, index) in appAllowedInboundPorts: {
    name: 'Allow-Mgmt-To-App-${port}'
    properties: {
      description: 'Allow management subnet to reach the application subnet on TCP ${port}.'
      priority: 100 + (index * 10)
      access: 'Allow'
      direction: 'Inbound'
      protocol: 'Tcp'
      sourcePortRange: '*'
      destinationPortRange: port
      sourceAddressPrefix: managementSubnetPrefix
      destinationAddressPrefix: appSubnetPrefix
    }
  }
]
var denyAllInboundRule = {
  name: 'Deny-All-Inbound'
  properties: {
    description: 'Explicit default-deny inbound rule for Zero Trust segmentation.'
    priority: 4096
    access: 'Deny'
    direction: 'Inbound'
    protocol: '*'
    sourcePortRange: '*'
    destinationPortRange: '*'
    sourceAddressPrefix: '*'
    destinationAddressPrefix: '*'
  }
}

@description('NSG for application subnet with explicit management-to-app allow rules.')
resource appNetworkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: appNsgName
  location: location
  tags: tags
  properties: {
    securityRules: concat(appAllowInboundRules, [
      denyAllInboundRule
    ])
  }
}

@description('NSG for management subnet with explicit default-deny inbound rule.')
resource managementNetworkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: managementNsgName
  location: location
  tags: tags
  properties: {
    securityRules: [
      denyAllInboundRule
    ]
  }
}

@description('NSG for private endpoint subnet with explicit default-deny inbound rule.')
resource privateEndpointNetworkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: privateEndpointNsgName
  location: location
  tags: tags
  properties: {
    securityRules: [
      denyAllInboundRule
    ]
  }
}

@description('Virtual network with application, management, and private endpoint subnets.')
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-07-01' = {
  name: effectiveVnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: vnetAddressPrefixes
    }
    subnets: [
      {
        name: appSubnetName
        properties: {
          addressPrefix: appSubnetPrefix
          networkSecurityGroup: {
            id: appNetworkSecurityGroup.id
          }
          privateEndpointNetworkPolicies: 'Enabled'
        }
      }
      {
        name: managementSubnetName
        properties: {
          addressPrefix: managementSubnetPrefix
          networkSecurityGroup: {
            id: managementNetworkSecurityGroup.id
          }
          privateEndpointNetworkPolicies: 'Enabled'
        }
      }
      {
        name: privateEndpointSubnetName
        properties: {
          addressPrefix: privateEndpointSubnetPrefix
          networkSecurityGroup: {
            id: privateEndpointNetworkSecurityGroup.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

@description('Virtual network resource ID.')
output vnetResourceId string = virtualNetwork.id

@description('Subnet resource IDs keyed by subnet purpose.')
output subnetResourceIds object = {
  app: resourceId('Microsoft.Network/virtualNetworks/subnets', effectiveVnetName, appSubnetName)
  management: resourceId('Microsoft.Network/virtualNetworks/subnets', effectiveVnetName, managementSubnetName)
  privateEndpoints: resourceId('Microsoft.Network/virtualNetworks/subnets', effectiveVnetName, privateEndpointSubnetName)
}

@description('Network security group resource IDs keyed by subnet purpose.')
output networkSecurityGroupResourceIds object = {
  app: appNetworkSecurityGroup.id
  management: managementNetworkSecurityGroup.id
  privateEndpoints: privateEndpointNetworkSecurityGroup.id
}
