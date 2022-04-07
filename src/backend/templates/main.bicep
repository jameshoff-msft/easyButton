param location string
param projectName string 
param repositoryToken string
param repositoryUrl string
param formrecApiKey string
param formrecEndpoint string
param branch string = 'main'

param cosmosDbName string = projectName
param cosmosContainerName string = projectName
param storageAccountName string = projectName
param cosmosdbAccountName string = projectName
param hostingPlanName string = projectName
param functionAppName string = projectName
param functionAppNamePython string = 'huggingface${projectName}'
param applicationInsightsName string = 'appinsights${projectName}'
param cogServicesName string = 'cogservices${projectName}'
param languageServicesName string = 'language${projectName}'
param webAppName string = toLower('webapp${projectName}')


// cosmos db names
param accountName string = projectName
param databaseName string = cosmosDbName
param containerName string = cosmosContainerName
param primaryRegion string = location
// param secondaryRegion string 

//language services
param languageServicesLocation string = 'westus2' //fixed...not available everywhere
//param languageStudioProjectName string = projectName


@allowed([
  'nonprod'
  'prod'
])
param environmentType string = 'nonprod'

var storageAccountSkuName = (environmentType == 'prod') ? 'Standard_GRS' : 'Standard_LRS'

resource storageAccount 'Microsoft.Storage/storageAccounts@2021-08-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: storageAccountSkuName
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
  }
}

resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2021-08-01' = {
  name: 'default'
  parent: storageAccount
}

resource blobContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-08-01' = {
  name: 'test'
  parent: blobServices
}




@description('The default consistency level of the Cosmos DB account.')
@allowed([
  'Eventual'
  'ConsistentPrefix'
  'Session'
  'BoundedStaleness'
  'Strong'
])
param defaultConsistencyLevel string = 'Session'

@description('Max stale requests. Required for BoundedStaleness. Valid ranges, Single Region: 10 to 1000000. Multi Region: 100000 to 1000000.')
@minValue(10)
@maxValue(2147483647)
param maxStalenessPrefix int = 100000

@description('Max lag time (minutes). Required for BoundedStaleness. Valid ranges, Single Region: 5 to 84600. Multi Region: 300 to 86400.')
@minValue(5)
@maxValue(86400)
param maxIntervalInSeconds int = 300

@description('Enable automatic failover for regions')
param automaticFailover bool = true



@description('Maximum throughput for the container')
@minValue(4000)
@maxValue(1000000)
param autoscaleMaxThroughput int = 4000

var accountName_var = toLower(accountName)
var consistencyPolicy = {
  Eventual: {
    defaultConsistencyLevel: 'Eventual'
  }
  ConsistentPrefix: {
    defaultConsistencyLevel: 'ConsistentPrefix'
  }
  Session: {
    defaultConsistencyLevel: 'Session'
  }
  BoundedStaleness: {
    defaultConsistencyLevel: 'BoundedStaleness'
    maxStalenessPrefix: maxStalenessPrefix
    maxIntervalInSeconds: maxIntervalInSeconds
  }
  Strong: {
    defaultConsistencyLevel: 'Strong'
  }
}
var locations = [
  {
    locationName: primaryRegion
    failoverPriority: 0
    isZoneRedundant: false
  }
  // {
  //   locationName: secondaryRegion
  //   failoverPriority: 1
  //   isZoneRedundant: false
  // }
]

resource accountName_resource 'Microsoft.DocumentDB/databaseAccounts@2021-01-15' = {
  name: accountName_var
  kind: 'GlobalDocumentDB'
  location: location
  properties: {
    consistencyPolicy: consistencyPolicy[defaultConsistencyLevel]
    locations: locations
    databaseAccountOfferType: 'Standard'
    enableAutomaticFailover: automaticFailover
  }
}

resource accountName_databaseName 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2021-01-15' = {
  parent: accountName_resource
  name: databaseName
  properties: {
    resource: {
      id: databaseName
    }
  }
}

resource accountName_databaseName_containerName 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2021-01-15' = {
  parent: accountName_databaseName
  name: containerName
  properties: {
    resource: {
      id: containerName
      partitionKey: {
        paths: [
          '/records'
        ]
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        includedPaths: [
          {
            path: '/*'
          }
        ]
        excludedPaths: [
          {
            path: '/myPathToNotIndex/*'
          }
        ]
      }
      defaultTtl: 86400
    }
    options: {
      autoscaleSettings: {
        maxThroughput: autoscaleMaxThroughput
      }
    }
  }
}

resource cogServicesAccount 'Microsoft.CognitiveServices/accounts@2021-10-01' = {
  name: cogServicesName
  location: location
  sku: {
    name: 'S0'
    tier: 'Standard'
  }
  kind: 'CognitiveServices'
  properties:{

  }
}



resource languageServicesAccount 'Microsoft.CognitiveServices/accounts@2021-10-01' = {
  name: languageServicesName
  location: languageServicesLocation
  sku: {
    name: 'S'
  }
  kind: 'TextAnalytics'
  properties:{

  }
}



////////////////////////////////////

resource hostingPlan 'Microsoft.Web/serverfarms@2020-10-01' = {
  name: hostingPlanName
  location: location
  kind: 'linux'
  sku: {
    name: 'B1' 
    tier: 'Basic'
  }
  properties: {
    reserved: true
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: location
  kind: 'string'
  properties: {
    Application_Type: 'web'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

resource functionAppPython 'Microsoft.Web/sites@2020-06-01' = {
  name: functionAppNamePython
  location: location
  kind: 'functionapp'
  properties: {
    httpsOnly: true
    serverFarmId: hostingPlan.id
    clientAffinityEnabled: true
    siteConfig: {
      linuxFxVersion: 'Python|3.9'
      alwaysOn: true
      appSettings: [
        {
          'name': 'APPINSIGHTS_INSTRUMENTATIONKEY'
          'value': appInsights.properties.InstrumentationKey
        }
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${listKeys(storageAccount.id, storageAccount.apiVersion).keys[0].value}'
        }
        {
          'name': 'FUNCTIONS_EXTENSION_VERSION'
          'value': '~4'
        }
        {
          'name': 'BUILD_FLAGS'
          'value': 'UseExpressBuild'
        }
        {
          'name': 'ENABLE_ORYX_BUILD'
          'value': 'true'
        }
        {
          'name': 'FUNCTIONS_WORKER_RUNTIME'
          'value': 'python'
        }
        {
          'name': 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          'value': '1'
        }
        {
          'name': 'XDG_CACHE_HOME'
          'value': '/tmp/.cache'
        }
      ]
    }
  }

  dependsOn: [

  ]
}

resource functionApp 'Microsoft.Web/sites@2020-06-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  
  properties: {
    httpsOnly: true
    serverFarmId: hostingPlan.id
    clientAffinityEnabled: true
    siteConfig: {
      appSettings: [
        {
          'name': 'APPINSIGHTS_INSTRUMENTATIONKEY'
          'value': appInsights.properties.InstrumentationKey
        }
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${listKeys(storageAccount.id, storageAccount.apiVersion).keys[0].value}'
        }
        {
          'name': 'FUNCTIONS_EXTENSION_VERSION'
          'value': '~4'
        }
        {
          'name': 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          'value': 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${listKeys(storageAccount.id, storageAccount.apiVersion).keys[0].value}'
        }
        {
          'name': 'FUNCTIONS_WORKER_RUNTIME'
          'value': 'node'
        }
        {
          'name': 'WEBSITE_NODE_DEFAULT_VERSION'
          'value': '~14'
        }
        {
          'name': 'BLOB_STORAGE_CONTAINER'
          'value': blobContainer.name
        }
        {
          'name': 'COSMOSDB_CONNECTION_STRING'
          'value': 'AccountEndpoint=https://${cosmosdbAccountName}.documents.azure.com:443/;AccountKey=${listKeys(accountName_resource.id, accountName_resource.apiVersion).primaryMasterKey};'
        }
        {
          'name': 'COSMOSDB_CONTAINER_NAME'
          'value': cosmosContainerName
        }
        {
          'name': 'COSMOSDB_DB_NAME'
          'value': cosmosDbName
        }
        {
          'name': 'OCR_ENDPOINT'
          'value': cogServicesAccount.properties.endpoint
        }
        {
          'name': 'OCR_APIKEY'
          'value': listKeys(cogServicesAccount.id, cogServicesAccount.apiVersion).key1
        }
        {
          'name': 'LANGUAGE_STUDIO_PREBUILT_ENDPOINT'
          'value': languageServicesAccount.properties.endpoint
        }
        {
          'name': 'LANGUAGE_STUDIO_PREBUILT_APIKEY'
          'value': listKeys(languageServicesAccount.id, languageServicesAccount.apiVersion).key1
        }
        {
          'name': 'LANGUAGE_STUDIO_ENDPOINT'
          'value': 'https://airangerslangcnerdemo.cognitiveservices.azure.com/text/analytics/v3.2-preview.2/analyze'  //languageServicesAccount.properties.endpoint
        }
        {
          'name': 'LANGUAGE_STUDIO_APIKEY'
          'value': '139f689301d8486d980c6ab17b773368' //listKeys(languageServicesAccount.id, languageServicesAccount.apiVersion).key1
        }
        {
          'name': 'LANGUAGE_STUDIO_PROJECT'
          'value': 'airangerscner4' //languageStudioProjectName
        }
        {
          'name': 'FORMREC_APIKEY'
          'value': formrecApiKey
        }
        {
          'name': 'FORMREC_ENDPOINT'
          'value': formrecEndpoint
        }
        {
          'name': 'SPEECH_SUB_KEY'
          'value': listKeys(cogServicesAccount.id, cogServicesAccount.apiVersion).key1
        }
        {
          'name': 'SPEECH_SUB_REGION'
          'value': cogServicesAccount.location
        }
        {
          'name': 'TRANSLATE_APIKEY'
          'value': listKeys(cogServicesAccount.id, cogServicesAccount.apiVersion).key1
        }
        {
          'name': 'TRANSLATE_REGION'
          'value': cogServicesAccount.location
        }
        {
          'name' : 'TRANSLATE_ENDPOINT'
          'value' : 'https://api.cognitive.microsofttranslator.com/'
        }
        {
          'name' : 'HUGGINGFACE_ENDPOINT'
          'value' : 'https://${functionAppNamePython}.azurewebsites.net'
        }
        // WEBSITE_CONTENTSHARE will also be auto-generated - https://docs.microsoft.com/en-us/azure/azure-functions/functions-app-settings#website_contentshare
        // WEBSITE_RUN_FROM_PACKAGE will be set to 1 by func azure functionapp publish
      ]
    }
  }

  dependsOn: [

  ]
}


resource staticWebApp 'Microsoft.Web/staticSites@2020-12-01' = {
  name: webAppName
  location: 'eastus2'
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  properties: {
    // The provider, repositoryUrl and branch fields are required for successive deployments to succeed
    // for more details see: https://github.com/Azure/static-web-apps/issues/516
    provider: 'GitHub'
    repositoryUrl: repositoryUrl
    repositoryToken: repositoryToken
    branch: branch
    buildProperties: {
      apiLocation: 'api'
    }
  }
}

resource staticWebAppSettings 'Microsoft.Web/staticSites/config@2021-03-01' = {
  name: 'appsettings'
  kind: 'staticWebAppSettings'
  parent: staticWebApp
  
  properties: {
      'COSMOS_DB_CONNECTION_STRING' : 'AccountEndpoint=https://${cosmosdbAccountName}.documents.azure.com:443/;AccountKey=${listKeys(accountName_resource.id, accountName_resource.apiVersion).primaryMasterKey};'
      'COSMOS_DB_DB' : cosmosDbName
      'COSMOS_DB_CONTAINER' : cosmosContainerName
      'BLOB_STORAGE_CONNECTION_STRING' : 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${listKeys(storageAccount.id, storageAccount.apiVersion).keys[0].value}'
      'BLOB_STORAGE_CONTAINER' : blobContainer.name
  }
}
