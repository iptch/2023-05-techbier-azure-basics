param resourceNameBody string = 'tb-azbasics'

@description('Something unique like your initials or short name (e.g. "jsc")')
param resourceNameSuffix string

param resourceLocation string = resourceGroup().location

param alertReceiverName string = 'Foo Bar'

param alertReceiverEmail string = 'foo@bar.ch'

@description('Metric name dispatched in code to indicate usage of get file function')
param downloadMetricName string = 'Download'

var storageAccountName = replace('st-${resourceNameBody}-${resourceNameSuffix}', '-', '')
var storageBlobContainerName = 'files'

var funcAppName = 'func-${resourceNameBody}-${resourceNameSuffix}'

var keyVaultName = 'kv-${resourceNameBody}-${resourceNameSuffix}'
var keyVaultSecretStorageAccountConnectionString = 'StorageConnectionString'

resource logAnalyticsWsRes 'Microsoft.OperationalInsights/workspaces@2021-12-01-preview' = {
  name: 'log-${resourceNameBody}-${resourceNameSuffix}'
  location: resourceLocation
  properties: {
    sku: {
      name: 'pergb2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: -1
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

resource appInsightsRes 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-${resourceNameBody}-${resourceNameSuffix}'
  location: resourceLocation
  kind: 'web'
  properties: {
    Application_Type: 'web'
    RetentionInDays: 90
    WorkspaceResourceId: logAnalyticsWsRes.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

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

resource keyVaultRes 'Microsoft.KeyVault/vaults@2022-11-01' = {
  name: keyVaultName
  location: resourceLocation
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: funcAppRes.identity.principalId
        permissions: {
          certificates: []
          keys: []
          secrets: [
            'get'
          ]
        }
      }
    ]
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enableRbacAuthorization: false
    publicNetworkAccess: 'Enabled'
  }
}

resource keyVaultDiagnosticsRes 'Microsoft.Insights/diagnosticSettings@2017-05-01-preview' = {
  name: 'LogAnalytics'
  scope: keyVaultRes
  properties: {
    workspaceId: logAnalyticsWsRes.id
    logs: [
      {
        category: 'AuditEvent'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

resource keyVaultSecretStorageAccountConnectionStringRes 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = {
  parent: keyVaultRes
  name: keyVaultSecretStorageAccountConnectionString
  properties: {
    value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};AccountKey=${storageAccountRes.listKeys().keys[0].value}'
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
  identity: {
    type: 'SystemAssigned'
  }
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
    AzureWebJobsStorage: '@Microsoft.KeyVault(VaultName=${keyVaultName};SecretName=${keyVaultSecretStorageAccountConnectionString})'
    WEBSITE_CONTENTAZUREFILECONNECTIONSTRING: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};AccountKey=${storageAccountRes.listKeys().keys[0].value}'
    APPLICATIONINSIGHTS_CONNECTION_STRING: appInsightsRes.properties.ConnectionString
    FUNCTIONS_EXTENSION_VERSION: '~4'
    FUNCTIONS_WORKER_RUNTIME: 'dotnet'
    WEBSITE_TIME_ZONE: 'W. Europe Standard Time'
    WEBSITE_CONTENTSHARE: funcAppName
    StorageConnectionString: '@Microsoft.KeyVault(VaultName=${keyVaultName};SecretName=${keyVaultSecretStorageAccountConnectionString})'
    StorageBlobContainer: storageBlobContainerName
    DownloadMetricName: downloadMetricName
  }
  dependsOn: [
    keyVaultSecretStorageAccountConnectionStringRes
  ]
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
      'function.proj': loadTextContent('../source/function.proj')
      'run.csx': loadTextContent('../source/listing-advanced.run.csx')
    }
    test_data: '{"method":"get","queryStringParams":[],"headers":[],"body":""}'
    invoke_url_template: 'https://${funcAppName}.azurewebsites.net/api/files'
    language: 'CSharp'
    isDisabled: false
  }
}

resource funcGetFileRes 'Microsoft.Web/sites/functions@2022-03-01' = {
  parent: funcAppRes
  name: 'GetFile'
  properties: {
    config: {
      bindings: [
        {
          name: 'req'
          route: 'files/{filename}'
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
      'function.proj': loadTextContent('../source/function.proj')
      'run.csx': loadTextContent('../source/detail.run.csx')
    }
    test_data: '{"method":"get","queryStringParams":[{"name":"filename","value":"test.png"}],"headers":[],"body":""}'
    invoke_url_template: 'https://${funcAppName}.azurewebsites.net/api/files/{filename}'
    language: 'CSharp'
    isDisabled: false
  }
}

resource actionGroupRes 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-${resourceNameBody}-${resourceNameSuffix}'
  location: 'Global'
  properties: {
    groupShortName: 'TechBier'
    enabled: true
    emailReceivers: [
      {
        name: alertReceiverName
        emailAddress: alertReceiverEmail
      }
    ]
  }
}

resource alertRuleRes 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'ar-${resourceNameBody}-${resourceNameSuffix}'
  location: 'global'
  properties: {
    description: 'Notification when > 5 file downloads per hour'
    severity: 3
    enabled: true
    scopes: [
      appInsightsRes.id
    ]
    evaluationFrequency: 'PT30M'
    windowSize: 'PT1H'
    criteria: {
      allOf: [
        {
          threshold: 5
          name: 'Metric1'
          metricNamespace: 'Azure.ApplicationInsights'
          metricName: downloadMetricName
          operator: 'GreaterThan'
          timeAggregation: 'Total'
          skipMetricValidation: false
          criterionType: 'StaticThresholdCriterion'
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
    }
    autoMitigate: false
    targetResourceType: 'microsoft.insights/components'
    targetResourceRegion: resourceLocation
    actions: [
      {
        actionGroupId: actionGroupRes.id
        webHookProperties: {
        }
      }
    ]
  }
}

output userApiEndpoint string = 'https://${funcAppName}.azurewebsites.net/api/files'
output operatorStorageBrowserEndpoint string = '${environment().portal}/#@${subscription().tenantId}/resource${storageAccountRes.id}/storagebrowser'
