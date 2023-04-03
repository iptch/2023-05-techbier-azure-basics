param resourceNameBody string = 'tb-azbasics'

@description('Something unique like your initials or short name (e.g. "jsc")')
param resourceNameSuffix string

param resourceLocation string = resourceGroup().location

var storageAccountName = replace('st-${resourceNameBody}-${resourceNameSuffix}', '-', '')
var storageBlobContainerName = 'files'

var funcAppName = 'func-${resourceNameBody}-${resourceNameSuffix}'

resource storageAccountRes 'Microsoft.Storage/storageAccounts@2022-09-01' = {
  name: storageAccountName
  location: resourceLocation
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    dnsEndpointType: 'Standard'
    defaultToOAuthAuthentication: false
    publicNetworkAccess: 'Enabled'
    allowCrossTenantReplication: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: true
    allowSharedKeyAccess: true
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
    supportsHttpsTrafficOnly: true
    encryption: {
      requireInfrastructureEncryption: false
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    accessTier: 'Hot'
  }
}

resource storageAccountBlobSvcRes 'Microsoft.Storage/storageAccounts/blobServices@2022-09-01' = {
  parent: storageAccountRes
  name: 'default'
  properties: {
    changeFeed: {
      enabled: false
    }
    restorePolicy: {
      enabled: false
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    cors: {
      corsRules: []
    }
    deleteRetentionPolicy: {
      allowPermanentDelete: false
      enabled: true
      days: 7
    }
    isVersioningEnabled: false
  }
}

resource storageAccountBlobContainerRes 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01' = {
  parent: storageAccountBlobSvcRes
  name: storageBlobContainerName
  properties: {
    publicAccess: 'None'
  }
}

resource appServicePlanRes 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: 'asp-${resourceNameBody}-${resourceNameSuffix}'
  location: resourceLocation
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  kind: 'functionapp'
  properties: {}
}

resource funcAppRes 'Microsoft.Web/sites@2022-03-01' = {
  name: funcAppName
  location: resourceLocation
  kind: 'functionapp'
  properties: {
    enabled: true
    hostNameSslStates: [
      {
        name: '${funcAppName}.azurewebsites.net'
        sslState: 'Disabled'
        hostType: 'Standard'
      }
      {
        name: '${funcAppName}.scm.azurewebsites.net'
        sslState: 'Disabled'
        hostType: 'Repository'
      }
    ]
    serverFarmId: appServicePlanRes.id
    siteConfig: {
      functionAppScaleLimit: 200
      minimumElasticInstanceCount: 0
      ftpsState: 'Disabled'
    }
    containerSize: 1536
    dailyMemoryTimeQuota: 0
    httpsOnly: true
    redundancyMode: 'None'
    publicNetworkAccess: 'Enabled'
    keyVaultReferenceIdentity: 'SystemAssigned'
  }
}

resource funcAppSettingsRes 'Microsoft.Web/sites/config@2022-03-01' = {
  parent: funcAppRes
  name: 'appsettings'
  properties: {
    AzureWebJobsStorage: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};AccountKey=${storageAccountRes.listKeys().keys[0].value}'
    WEBSITE_CONTENTAZUREFILECONNECTIONSTRING: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};AccountKey=${storageAccountRes.listKeys().keys[0].value}'
    FUNCTIONS_EXTENSION_VERSION: '~4'
    FUNCTIONS_WORKER_RUNTIME: 'dotnet'
    WEBSITE_TIME_ZONE: 'W. Europe Standard Time'
    WEBSITE_CONTENTSHARE: funcAppName
    StorageConnectionString: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};AccountKey=${storageAccountRes.listKeys().keys[0].value}'
    StorageBlobContainer: storageBlobContainerName
  }
}

resource funcListFilesRes 'Microsoft.Web/sites/functions@2022-03-01' = {
  parent: funcAppRes
  name: 'ListFiles'
  properties: {
    config: {
      bindings: [
        {
          name: 'req'
          route: 'files'
          type: 'httpTrigger'
          direction: 'in'
          authLevel: 'anonymous'
          methods: [
            'get'
          ]
        }
        {
          name: '$return'
          type: 'http'
          direction: 'out'
        }
      ]
    }
    files: {
      'function.proj': loadTextContent('../source/list-files/function.proj')
      'run.csx': loadTextContent('../source/list-files/run.csx')
    }
    test_data: '{"method":"get","queryStringParams":[],"headers":[],"body":""}'
    invoke_url_template: 'https://${funcAppName}.azurewebsites.net/api/files'
    language: 'CSharp'
    isDisabled: false
  }
}

output userApiEndpoint string = 'https://${funcAppName}.azurewebsites.net/api/files'
output operatorStorageBrowserEndpoint string = '${environment().portal}/#@${subscription().tenantId}/resource${storageAccountRes.id}/storagebrowser'
