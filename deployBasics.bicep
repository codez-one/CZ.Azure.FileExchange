param name string
param location string  = resourceGroup().location

resource storage 'Microsoft.Storage/storageAccounts@2021-06-01' = {
  name: uniqueString(resourceGroup().id, '7f358957-c1be-48ad-8902-808564e0556f')
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {}
}

resource website 'Microsoft.Web/staticSites@2021-02-01' = {
  name: name
  location: location
  sku: {
    name: 'Free'
    tier: 'Free'
  }
  properties: {}
}

resource websiteconfig 'Microsoft.Web/staticSites/config@2021-02-01' = {
  dependsOn: [
    storage
  ]
  parent: website
  name: 'functionappsettings'
  properties: {
    StorageConnectionString: 'DefaultEndpointsProtocol=https;AccountName=${storage.name};AccountKey=${storage.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
  }
}

resource storageBlobServiceConfig 'Microsoft.Storage/storageAccounts/blobServices@2021-08-01' = {
  parent: storage
  name: 'default'
  properties: {
    lastAccessTimeTrackingPolicy:{
      enable: true
    }
    cors: {
      corsRules: [
        {
          allowedOrigins: [
            'https://${website.properties.defaultHostname}'
            'https://*.${location}.azurestaticapps.net'
          ]
          exposedHeaders: [
            '*'
          ]
          maxAgeInSeconds: 0
          allowedMethods: [
            'GET'
            'PUT'
            'OPTIONS'
          ]
          allowedHeaders: [
            '*'
          ]
        }
      ]
    }
  }
}

resource storageSaveMonyPolicy 'Microsoft.Storage/storageAccounts/managementPolicies@2021-08-01' = {
  parent: storage
  name: 'default'
  dependsOn: [
    storageBlobServiceConfig
  ]
  properties: {
    policy: {
      rules: [
        {
          type: 'Lifecycle'
          name: 'save money'
          definition: {
            actions: {
              baseBlob: {
                tierToCool: {
                  daysAfterLastAccessTimeGreaterThan: 10
                }
                tierToArchive: {
                  daysAfterLastAccessTimeGreaterThan: 30
                }
                enableAutoTierToHotFromCool: true
                delete: {
                  daysAfterLastAccessTimeGreaterThan: 365
                }
              }
            }
            filters:{
              blobTypes: [
                'blockBlob'
              ]
            }
          }
        }
      ]
    }
  }
}


output website object = website
output storage object = storage
