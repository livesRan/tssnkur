@description('Azure Region')
param location string = 'southeastasia'

@description('Resource tags')
param tags object = {
  Environment: 'test'
  Project: 'tssnkur'
}

@description('MySQL admin username')
param adminUsername string = 'mysqladmin'

@secure()
@description('MySQL admin password, hardcoded for TEST ONLY, never use in production')
param adminPassword string = 'Test@Passw0rd123'

@description('MySQL storage size GB')
param storageSizeGB int = 32

@description('VNet address space')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('MySQL subnet prefix')
param dbSubnetPrefix string = '10.0.1.0/24'

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: 'vnet-tssnkur-prod'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
  }
}

// Delegate subnet for MySQL Flexible Server
resource dbSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  name: 'snet-db-tssnkur-prod'
  parent: vnet
  properties: {
    addressPrefix: dbSubnetPrefix
    delegations: [
      {
        name: 'mysql-delegation'
        properties: {
          serviceName: 'Microsoft.DBforMySQL/flexibleServers'
        }
      }
    ]
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
}

// Private DNS Zone for MySQL Flexible Server
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2023-09-01' = {
  name: 'privatelink.mysql.database.azure.com'
  location: 'global'
  tags: tags
}

// Private DNS Zone VNet Link
resource privateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2023-09-01' = {
  name: 'link-vnet-tssnkur-prod'
  parent: privateDnsZone
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}

// MySQL Flexible Server, southeastasia supported version: 8.0.34
resource mysqlServer 'Microsoft.DBforMySQL/flexibleServers@2023-12-30' = {
  name: 'tssnkur-mysql-prod'
  location: location
  tags: tags
  sku: {
    name: 'Standard_B1ms'
    tier: 'Burstable'
  }
  properties: {
    administratorLogin: adminUsername
    administratorLoginPassword: adminPassword
    version: '8.0.34'
    network: {
      delegatedSubnetResourceId: dbSubnet.id
      privateDnsZoneResourceId: privateDnsZone.id
      publicNetworkAccess: 'Disabled'
    }
    storage: {
      storageSizeGB: storageSizeGB
      iops: 360
      autoGrow: 'Enabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
  }
  dependsOn: [
    privateDnsZoneLink
  ]
}

// Outputs
output mysqlFqdn string = mysqlServer.properties.fullyQualifiedDomainName
output mysqlAdminUser string = adminUsername
output vnetId string = vnet.id
output dbSubnetId string = dbSubnet.id
