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
    webSiteName: last(split(basics.outputs.website.resourceId, '/'))
    location: location
  }
}

module events 'deployEvent.bicep' = {
  name: 'archival event deployment'
  dependsOn: [
    webappDeployment
  ]
  params: {
    baseUrl: webappDeployment.outputs.staticWebAppHost
    location: location
    storageAccountName: last(split(basics.outputs.storage.resourceId, '/'))
  }
}
