param name string
param location string  = resourceGroup().location
@secure()
param githubToken string
param branch string
param runId int
param prNumber string


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
    githubToken: githubToken
    branch: branch
    githubArtifactName: 'artifact'
    githubRunId: string(runId)
    prNumber: prNumber
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
