param name string
param location string  = resourceGroup().location
@secure()
param githubToken string
param branch string
param runId int
param prNumber string
param githubRuntimeApiUrl string


module basics 'deployBasics.bicep' = {
  name: 'basics'
  params: {
    name: name
    location: location
  }
}

module webappDeployment 'deploayWebApp.bicep' = {
  name: 'webappdeployment'
  params: {
    githubToken: githubToken
    branch: branch
    githubRuntimeApiUrl: githubRuntimeApiUrl
    githubArtifactName: 'artifact'
    githubRunId: string(runId)
    prNumber: prNumber
    webSiteName: last(split(basics.outputs.website.resourceId, '/'))
    location: location
  }
}

module events 'deployEvent.bicep' = {
  name: 'archivalventdeployment'
  dependsOn: [
    webappDeployment
  ]
  params: {
    baseUrl: webappDeployment.outputs.staticWebAppHost
    prNumber: prNumber
    location: location
    storageAccountName: last(split(basics.outputs.storage.resourceId, '/'))
  }
}
