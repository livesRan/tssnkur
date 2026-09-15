// ==============================================================================
// BICEP TEST TEMPLATE: Auto deploy VNet + Subnet + PrivateDNS + MySQL + 1 Test VM
// !!! TEST ONLY, Password hardcoded, DO NOT COMMIT TO GIT / PRODUCTION !!!
// Fixed: MySQL api-version + AvailabilitySet Aligned SKU
// ==============================================================================
@description('Azure Region')
param location string = 'southeastasia'

@description('MySQL Flexible Server admin login name')
param adminUsername string = 'tssnkuradmin'

@description('MySQL admin password, FOR TEST ONLY')
@secure()
param adminPassword string = 'Test@123456'

@description('MySQL storage size GB')
param storageSizeGB int = 512

@description('Linux VM admin username')
param vmAdminUsername string = 'azureuser'

@description('SSH public key for VM login, TEST DEFAULT')
param vmSshPublicKey string = 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDAfakeKeyForTestOnly'

var tags = {
  Environment: 'Test'
  Project: 'EduFlowDBMigration'
  CostCenter: 'Engineering'
}

// --------------------------
// 1. 自动部署 VNet
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
// 2. 两个子网
// --------------------------
// MySQL委托子网（必须delegated给MySQL Flexible Server）
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

// App VM子网
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
  dependsOn: [vnet]
}

// --------------------------
// 4. MySQL Flexible Server (修复API版本：2023-12-30 去掉-preview)
// --------------------------
resource mysqlServer 'Microsoft.DBforMySQL/flexibleServers@2023-12-30' = {
  name: 'tssnkur-mysql-prod'
  location: location
  tags: tags
  sku: {
    name: 'Standard_D8ds_v4'
    tier: 'BusinessCritical'
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
      iops: 20000
      autoGrow: 'Enabled'
    }
    highAvailability: {
      mode: 'ZoneRedundant'
      state: 'Enabled'
    }
    backup: {
      backupRetentionDays: 35
      geoRedundantBackup: 'Enabled'
    }
  }
  dependsOn: [dbSubnet, privateDnsZoneLink]
}

// --------------------------
// 5. App VM 资源：可用性集【增加Aligned SKU修复托管磁盘报错】+ 网卡 + 单台VM
// --------------------------
resource appAvailabilitySet 'Microsoft.Compute/availabilitySets@2023-09-01' = {
  name: 'as-tssnkur-app-prod'
  location: location
  tags: tags
  sku: {
    name: 'Aligned' // 关键修复：托管磁盘VM必须Aligned
  }
  properties: {
    platformUpdateDomainCount: 3
    platformFaultDomainCount: 2
  }
}

// 单张网卡，静态IP：10.1.1.11
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
  dependsOn: [appSubnet]
}]

// 单台CentOS7.9 VM
resource appVms 'Microsoft.Compute/virtualMachines@2023-09-01' = [for i in range(0,1): {
  name: 'app-web-${padLeft(string(i+1),2,'0')}'
  location: location
  tags: tags
  properties: {
    availabilitySet: {
      id: appAvailabilitySet.id
    }
    hardwareProfile: {
      vmSize: 'Standard_D4s_v3'
    }
    osProfile: {
      computerName: 'app-web-${padLeft(string(i+1),2,'0')}'
      adminUsername: vmAdminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${vmAdminUsername}/.ssh/authorized_keys'
              keyData: vmSshPublicKey
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
        name: 'app-web-${padLeft(string(i+1),2,'0')}-osdisk'
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
          id: appNics[i].id
        }
      ]
    }
  }
  dependsOn: [appNics]
}]

// --------------------------
// Outputs
// --------------------------
output mysqlFQDN string = mysqlServer.properties.fullyQualifiedDomainName
output mysqlAdminUser string = adminUsername
output vmPrivateIP string = appNics[0].properties.ipConfigurations[0].properties.privateIPAddress
output vnetName string = vnet.name
