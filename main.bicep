param name string
param location string  = resourceGroup().location
@secure()
param githubToken string = ''

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

resource deployIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'identityForAppDeployment'
  location: location
}

resource roleassignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(tenant().tenantId, resourceGroup().id, deployIdentity.id)
  scope: resourceGroup()
  properties: {
    principalId: deployIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    // this is the contributor role (magic numbers yeah)
    roleDefinitionId: '/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c'
  }
}

resource deployWebApp 'Microsoft.Resources/deploymentScripts@2020-10-01' = if(!empty(githubToken)) {
  name: 'deployWebApp'
  kind: 'AzurePowerShell'
  location: location
  dependsOn: [
    website
  ]
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${deployIdentity.name}': {}
    }
  }
  properties: {
    azPowerShellVersion: '8.3'
    retentionInterval: 'P1D'
    arguments: '-githubToken ${githubToken} -staticWebAppName ${name} -resourceGroupName ${resourceGroup().name}' //-branch ${branch} -githubRunId ${githubRunId} -githubArtifactName ${githubArtifactName}
    scriptContent: '''
    param(
      [string] $githubToken,
      # [string] $githubRunId,
      # [string] $githubArtifactName,
      [string] $staticWebAppName,
      [string] $resourceGroupName,
      [string] $branch
    )
    #if($branch -eq 'main'){
      # take stable releases here
      $result = Invoke-RestMethod https://api.github.com/repos/codez-one/CZ.Azure.FileExchange/releases/latest -Headers @{"Authorization" = "token $githubToken"; "X-GitHub-Api-Version" = "2022-11-28" }
      $frontendDownloadUrl = ($result.assets | ? {$_.name -like 'Frontend.zip'}).browser_download_url;
      $apiDownloadUrl = ($result.assets | ? {$_.name -like 'API.zip'}).browser_download_url;
      $deployDownloadUrl = ($result.assets | ? {$_.name -like 'deploy.ps1'}).browser_download_url
      New-Item -Type Directory artifact;
      Set-Location ./artifact/
      Invoke-WebRequest $frontendDownloadUrl -Headers @{"Authorization" = "token $githubToken"; "X-GitHub-Api-Version" = "2022-11-28" } -OutFile frontend.zip
      Invoke-WebRequest $apiDownloadUrl -Headers @{"Authorization" = "token $githubToken"; "X-GitHub-Api-Version" = "2022-11-28" } -OutFile api.zip
      Invoke-WebRequest $deployDownloadUrl -Headers @{"Authorization" = "token $githubToken"; "X-GitHub-Api-Version" = "2022-11-28" } -OutFile deploy.ps1
    #}else{
    #  throw 'currently we don't support deployment from stages'
    #  # download artifact from pipeline run
    #  # this is right now not used, because of limitations
    #  $result = Invoke-RestMethod https://api.github.com/repos/codez-one/CZ.Azure.FileExchange/actions/runs/$githubRunId/artifacts -Headers @{"Authorization" = "token $githubToken"; "X-GitHub-Api-Version" = "2022-11-28" }
    #  $result
    #  $artifact = $result.artifacts | ?{$_.name -eq $githubArtifactName}
    #  if($artifact -eq $null) {throw "artifact doesn't exsist."}
    #  $artifact.archive_download_url
    #  Invoke-WebRequest $artifact.archive_download_url -Headers @{"Authorization" = "token $githubToken"; "X-GitHub-Api-Version" = "2022-11-28" } -OutFile artifact.zip
    #  Expand-Archive artifact.zip
    #  Set-Location ./artifact/
    #}
    # deploy to webapp
    $secretProperties = Get-AzStaticWebAppSecret -Name $staticWebAppName -ResourceGroupName $resourceGroupName
    $token = $secretProperties.Property.Item("apiKey")
    $token.Substring(0,5)
    ./deploy.ps1 -Token $token -appBuildOutput ./frontend.zip -apiBuildOutput ./api.zip -apiFramework "dotnetisolated" -apiFrameworkVersion "7.0" -workingDir $pwd -Verbose
    '''
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

module events 'deployEvent.bicep' = {
  name: 'archival event deployment'
  dependsOn: [
    deployWebApp
  ]
  params: {
    baseUrl: 'https://${website.properties.defaultHostname}'
    location: location
    storageAccountName: storage.name
  }
}
