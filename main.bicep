param name string
param location string  = resourceGroup().location
@secure()
param githubToken string = 'empty'

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

// wie sollen wir hier den GitHub token bekommen?
resource deployWebApp 'Microsoft.Resources/deploymentScripts@2020-10-01' = if(githubToken != 'empty') {
  name: 'deployWebApp'
  kind: 'AzurePowerShell'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${deployIdentity.name}': {}
    }
  }
  properties: {
    azPowerShellVersion: '8.3'
    retentionInterval: 'P1D'
    arguments: '-githubToken ${resourceGroup().name}'
    scriptContent: '''
    param([string] $githubToken)
    # install github cli
    bash -c 'type -p curl >/dev/null || (apt update && apt install curl -y) && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg && echo \"deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && apt update && apt install gh -y'
    # download artifact
    gh auth login --with-token $githubToken
    gh run download RUN_ID -n ARTIFACT_NAME
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
