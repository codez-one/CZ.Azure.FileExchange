param name string

resource storage 'Microsoft.Storage/storageAccounts@2021-06-01' = {
  name: uniqueString(resourceGroup().id,'7f358957-c1be-48ad-8902-808564e0556f')
  location: resourceGroup().location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
}

resource website 'Microsoft.Web/staticSites@2021-02-01' = {
  name: name
  location: resourceGroup().location
  sku: {
    name: 'Free'
    tier: 'Free'
  }
  properties:{}
}

resource websiteconfig 'Microsoft.Web/staticSites/config@2021-02-01' ={
  dependsOn: [
    storage
  ]
  parent: website
  name: 'functionappsettings'
  properties: {
    StorageConnectionString: 'DefaultEndpointsProtocol=https;AccountName=${storage.name};AccountKey=${storage.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
  }
}
