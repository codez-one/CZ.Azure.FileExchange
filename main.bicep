param name string
param location string  = resourceGroup().location

module basics 'deployBasics.bicep' = {
  name: 'basics'
  params: {
    name: name
    location: location
  }
}

module webappDeployment 'deploayWebApp.bicep' = {
  name: 'deployment'
  params: {
    webSiteName: basics.outputs.website.name
    location: location
  }
}

module events 'deployEvent.bicep' = {
  name: 'archival event deployment'
  dependsOn: [
    webappDeployment
  ]
  params: {
    baseUrl: 'https://${basics.outputs.website.properties.defaultHostname}'
    location: location
    storageAccountName: basics.outputs.storage.name
  }
}
