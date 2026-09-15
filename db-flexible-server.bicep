@description('Azure Region')
param location string = 'southeastasia'
@description('Resource tags')
param tags object = {
  Environment: 'test'
  Project: 'tssnkur'
}
@description('MySQL admin username')
param adminUsername string = 'mysqladmin'
@description('MySQL admin password, TEST ONLY, hardcoded')
@secure()
param adminPassword string = 'Test@Passw0rd123'
@description('MySQL storage size GB')
param storageSizeGB int = 32
@description('VNet address space')
param vnetAddressPrefix string = '10.0.0.0/16'
@description('MySQL subnet prefix')
param dbSubnetPrefix string = '10.0.1.0/24'
@description('App subnet prefix')
param appSubnetPrefix string = '10.0.2.0/24'
@description('VM admin username')
param vmAdminUser string = 'azureuser'

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

// App Subnet for application VM
resource appSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  name: 'snet-app-tssnkur-prod'
  parent: vnet
  properties: {
    addressPrefix: appSubnetPrefix
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
}

// Private DNS Zone for MySQL Flexible Server
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.mysql.database.azure.com'
  location: 'global'
  tags: tags
}

// Private DNS Zone VNet Link
resource privateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  name: 'link-vnet-tssnkur-prod'
  parent: privateDnsZone
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}

// MySQL Flexible Server
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

// Network Interface for app VM
resource appNic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: 'app-web-01-nic'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: appSubnet.id
          }
          privateIPAllocationMethod: 'Static'
          privateIPAddress: '10.0.2.10'
        }
      }
    ]
  }
}

// Application VM
resource appVm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: 'app-web-01'
  location: location
  tags: tags
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B2ms'
    }
    osProfile: {
      computerName: 'app-web-01'
      adminUsername: vmAdminUser
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/azureuser/.ssh/authorized_keys'
              keyData: 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC2...'
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'OpenLogic'
        offer: 'CentOS'
        sku: '7_9-gen2'
        version: 'latest'
      }
      osDisk: {
        name: 'app-web-01-osdisk'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
        diskSizeGB: 100
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: appNic.id
        }
      ]
    }
  }
}

// Outputs
output mysqlFqdn string = mysqlServer.properties.fullyQualifiedDomainName
output mysqlAdminUser string = adminUsername
output vnetId string = vnet.id
output dbSubnetId string = dbSubnet.id
output appVmPrivateIP string = appNic.properties.ipConfigurations[0].properties.privateIPAddress
output appVmResourceId string = appVm.id
