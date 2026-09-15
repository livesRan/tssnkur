// ==============================================================================
// BICEP TEMPLATE FOR AZURE DATABASE FOR MYSQL FLEXIBLE SERVER WITH HA & VNET
// PROJECT: EduFlow LMS DB Migration (Tssnkur Technology Co Ltd)
// TEST VERSION: ONLY 1 APP VM + 1 NIC
// ==============================================================================
@description('部署资源所在的地理区域')
param location string = 'southeastasia'
@description('MySQL 灵活服务器的数据库管理员用户名')
param adminUsername string = 'tssnkuradmin'
@description('数据库管理员密码，值将从 Azure Key Vault 安全传入')
@secure()
param adminPassword string = 'Tssnkur_Admin_Secure_2025_Password'
@description('物理存储容量大小限制')
param storageSizeGB int = 512

// 定义统一打标的资源标签
var tags = {
  Environment: 'Production'
  Project: 'EduFlowDBMigration'
  Customer: 'Tssnkur Technology Co Ltd'
  CostCenter: 'Engineering'
  Owner: 'sarah.lim@tssnkur.com'
  ManagedBy: 'AzureMigrationConsulting'
}

// 引入原有的虚拟网络与专有子网资源 (通过 Existing 关联)
resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' existing = {
  name: 'vnet-tssnkur-prod'
  scope: resourceGroup()
}

resource dbSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' existing = {
  parent: vnet
  name: 'snet-db-private-endpoint'
}

// 创建私有 DNS 绑定区域，确保内网 FQDN 无缝解析
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.mysql.database.azure.com'
  location: 'global'
  tags: tags
}

// 将私有 DNS 链接至生产虚拟网络
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

// 核心数据库实例部署定义
resource mysqlServer 'Microsoft.DBforMySQL/flexibleServers@2023-12-30-preview' = {
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
    
    // 网络配置：完全启用私有网络集成，禁用外部公网
    network: {
      delegatedSubnetResourceId: dbSubnet.id
      privateDnsZoneResourceId: privateDnsZone.id
      publicNetworkAccess: 'Disabled'
    }
    
    // 存储规格配置与自动扩容
    storage: {
      storageSizeGB: storageSizeGB
      iops: 20000                   // 供给 20,000 IOPS 保障吞吐
      autoGrow: 'Enabled'           // 激活存储自动水位扩容
    }
    
    // 高可用双区冗余配置
    highAvailability: {
      mode: 'ZoneRedundant'
      state: 'Enabled'
    }
    
    // 自动备份参数：最大级 35 天留存，开启异地冗余备份
    backup: {
      backupRetentionDays: 35
      geoRedundantBackup: 'Enabled'
    }
  }
}

// 输出建成实例的核心 FQDN 信息，以便应用容器环境调取
output serverFullyQualifiedDomainName string = mysqlServer.properties.fullyQualifiedDomainName
output serverResourceId string = mysqlServer.id

// ==============================================================================
// APPLICATION INFRASTRUCTURE PROVISIONING (IaaS VM - 1 Node app-web-01)
// ==============================================================================
resource appSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' existing = {
  parent: vnet
  name: 'snet-app-prod'
}

resource appAvailabilitySet 'Microsoft.Compute/availabilitySets@2023-09-01' = {
  name: 'as-tssnkur-app-prod'
  location: location
  tags: tags
  properties: {
    platformUpdateDomainCount: 3
    platformFaultDomainCount: 2
  }
}

// 单网卡：app-web-01-nic，静态IP 10.1.1.11
resource appNics 'Microsoft.Network/networkInterfaces@2023-09-01' = [for i in range(0, 1): {
  name: 'app-web-${padLeft(string(i + 1), 2, '0')}-nic'
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
          privateIPAddress: '10.1.1.${string(i + 11)}'
        }
      }
    ]
  }
}]

// 单台VM：app-web-01
resource appVms 'Microsoft.Compute/virtualMachines@2023-09-01' = [for i in range(0, 1): {
  name: 'app-web-${padLeft(string(i + 1), 2, '0')}'
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
      computerName: 'app-web-${padLeft(string(i + 1), 2, '0')}'
      adminUsername: 'azureuser'
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
        name: 'app-web-${padLeft(string(i + 1), 2, '0')}-osdisk'
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
}]
