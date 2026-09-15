// ==============================================================================
// BICEP TEST TEMPLATE: VNet + Subnet + PrivateDNS + MySQL + 1 Test VM
// !!! TEST ONLY, Password hardcoded, DO NOT COMMIT TO GIT / PRODUCTION !!!
// Fixed: MySQL SKU + Remove invalid SSH key, use VM password login
// ==============================================================================
@description('Azure Region')
param location string = 'southeastasia'

@description('MySQL Flexible Server admin login name')
param adminUsername string = 'tssnkuradmin'

@description('MySQL admin password, FOR TEST ONLY')
@secure()
param adminPassword string = 'Test@123456'

@description('MySQL storage size GB')
param storageSizeGB int = 32

@description('Linux VM admin username')
param vmAdminUsername string = 'azureuser'

@description('VM password for test')
@secure()
param vmAdminPassword string = 'VmTest@123456'

var tags = {
  Environment: 'Test'
  Project: 'EduFlowDBMigration'
  CostCenter: 'Engineering'
}

// --------------------------
// 1. VNet
// --------------------------
resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: 'vnet-tssnkur-prod'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.1.0.0/16'
      ]
    }
  }
}

// --------------------------
// 2. Subnets
// --------------------------
resource dbSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  parent: vnet
  name: 'snet-db-private-endpoint'
  properties: {
    addressPrefix: '10.1.0.0/24'
    delegations: [
      {
        name: 'MySQLDelegation'
        properties: {
          serviceName: 'Microsoft.DBforMySQL/flexibleServers'
        }
      }
    ]
  }
}

resource appSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  parent: vnet
  name: 'snet-app-prod'
  properties: {
    addressPrefix: '10.1.1.0/24'
  }
}

// --------------------------
// 3. Private DNS Zone for MySQL + VNet Link
// --------------------------
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.mysql.database.azure.com'
  location: 'global'
  tags: tags
}

resource privateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: 'vnet-tssnkur-prod-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

// --------------------------
// 4. MySQL Flexible Server (Fixed SKU: GeneralPurpose + B1ms)
// --------------------------
resource mysqlServer 'Microsoft.DBforMySQL/flexibleServers@2023-12-30' = {
  name: 'tssnkur-mysql-prod'
  location: location
  tags: tags
  sku: {
    name: 'Standard_B1ms'
    tier: 'GeneralPurpose'
  }
  properties: {
    administratorLogin: adminUsername
    administratorLoginPassword: adminPassword
    version: '8.0.28'
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
}

// --------------------------
// 5. Availability Set + NIC + VM (Use password login, remove invalid SSH key)
// --------------------------
resource appAvailabilitySet 'Microsoft.Compute/availabilitySets@2023-09-01' = {
  name: 'as-tssnkur-app-prod'
  location: location
  tags: tags
  sku: {
    name: 'Aligned'
  }
  properties: {
    platformUpdateDomainCount: 3
    platformFaultDomainCount: 2
  }
}

resource appNics 'Microsoft.Network/networkInterfaces@2023-09-01' = [for i in range(0,1): {
  name: 'app-web-${padLeft(string(i+1),2,'0')}-nic'
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
          privateIPAddress: '10.1.1.${string(i+11)}'
        }
      }
    ]
  }
}]

resource appVms 'Microsoft.Compute/virtualMachines@2023-09-01' = [for i in range(0,1): {
  name: 'app-web-${padLeft(string(i+1),2,'0')}'
  location: location
  tags: tags
  properties: {
    availabilitySet: {
      id: appAvailabilitySet.id
    }
    hardwareProfile: {
      vmSize: 'Standard_B1s'
    }
    osProfile: {
      computerName: 'app-web-${padLeft(string(i+1),2,'0')}'
      adminUsername: vmAdminUsername
      adminPassword: vmAdminPassword // 使用密码登录，不再需要SSH公钥
      linuxConfiguration: {
        disablePasswordAuthentication: false // 开启密码登录测试
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
        name: 'app-web-${padLeft(string(i+1),2,'0')}-osdisk'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
        diskSizeGB: 30
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: appNics[i].id
        }
      ]
    }
  }
}]

output mysqlFQDN string = mysqlServer.properties.fullyQualifiedDomainName
output mysqlAdminUser string = adminUsername
output vmPrivateIP string = appNics[0].properties.ipConfigurations[0].properties.privateIPAddress
output vnetName string = vnet.name
