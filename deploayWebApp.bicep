param location string = resourceGroup().location
param webSiteName string


@secure()
param githubToken string = ''
param prNumber string = ''
param branch string = ''
param githubRuntimeApiUrl string = ''
param githubRunId string = ''
param githubArtifactName string = ''

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

resource deployPrWebApp 'Microsoft.Resources/deploymentScripts@2020-10-01' = if (!empty(prNumber) && !empty(branch) && !empty(githubToken)) {
  name: 'deployPrWebApp'
  kind: 'AzurePowerShell'
  dependsOn: [
    roleassignment
  ]
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
    arguments: '-githubToken ${githubToken} -staticWebAppName ${webSiteName} -resourceGroupName ${resourceGroup().name} -branch ${branch} -githubRunId ${githubRunId} -githubArtifactName ${githubArtifactName} -prNumber ${prNumber} -githubRuntimeApiUrl ${githubRuntimeApiUrl}'
    scriptContent: '''
    param(
      [string] $githubToken,
      [string] $githubRunId,
      [string] $githubRuntimeApiUrl,
      [string] $githubArtifactName,
      [string] $staticWebAppName,
      [string] $resourceGroupName,
      [string] $branch,
      [string] $prNumber
    )
    try{
      # download artifact from pipeline run
      $workflowArtifactUrl = "$($githubRuntimeApiUrl)_apis/pipelines/workflows/$githubRunId/artifacts";
      Write-Output "all artifacts: $workflowArtifactUrl";
      $result = Invoke-RestMethod $workflowArtifactUrl -Headers @{"Authorization" = "Bearer $githubToken"; "X-GitHub-Api-Version" = "2022-11-28" }
      Write-Output $result;
      $artifact = $result.value | ?{$_.name -eq $githubArtifactName}
      if($artifact -eq $null) {throw "artifact doesn't exsist."}
      Write-Output "ContainerURL: $($artifact.fileContainerResourceUrl)";
      $listOfArtifacts = Invoke-RestMethod $artifact.fileContainerResourceUrl -Headers @{"Authorization" = "Bearer $githubToken"; "X-GitHub-Api-Version" = "2022-11-28" }
      $listOfArtifacts = $listOfArtifacts.value
      $listOfArtifacts |%{
        $item = $_;
        Write-Output "try to download: $($item.path)";
        if($item.itemType -eq 'file'){
          Invoke-WebRequest $item.contentLocation -Headers @{"Authorization" = "Bearer $githubToken"; "X-GitHub-Api-Version" = "2022-11-28" } -OutFile $item.path
        }else{
          New-Item -Type Directory $item.path -Force
        }
      }
      Set-Location ./artifact/
      $secretProperties = Get-AzStaticWebAppSecret -Name $staticWebAppName -ResourceGroupName $resourceGroupName
      $token = $secretProperties.Property.Item("apiKey")
      ./deploy.ps1 -Token $token -appBuildOutput ./frontend.zip -apiBuildOutput ./api.zip -apiFramework "dotnetisolated" -apiFrameworkVersion "7.0" -workingDir $pwd -branchName $branch -envrionmentName $prNumber -Verbose
      # for azure Deployment Script output
      $DeploymentScriptOutputs = @{}
      $DeploymentScriptOutputs['staticWebUrl'] = (Get-AzStaticWebAppBuild -Name $staticWebAppName -ResourceGroupName $resourceGroupName -EnvironmentName $prNumber).Hostname
    }catch{
      Start-Sleep 30;
      Write-Host "there was an error";
      Write-Host $_;
    }
    '''
  }
}

resource deployWebApp 'Microsoft.Resources/deploymentScripts@2020-10-01' = if (empty(prNumber) || empty(branch) || empty(githubToken)){
  name: 'deployWebApp'
  kind: 'AzurePowerShell'
  dependsOn: [
    roleassignment
  ]
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
    arguments: '-staticWebAppName ${webSiteName} -resourceGroupName ${resourceGroup().name}'
    scriptContent: '''
    param(
      [string] $githubToken,
      [string] $staticWebAppName,
      [string] $resourceGroupName,
      [string] $branch
    )
    # take stable releases here
    $result = Invoke-RestMethod https://api.github.com/repos/codez-one/CZ.Azure.FileExchange/releases/latest -Headers @{"X-GitHub-Api-Version" = "2022-11-28" }
    $frontendDownloadUrl = ($result.assets | ? {$_.name -like 'Frontend.zip'}).browser_download_url;
    $apiDownloadUrl = ($result.assets | ? {$_.name -like 'API.zip'}).browser_download_url;
    $deployDownloadUrl = ($result.assets | ? {$_.name -like 'deploy.ps1'}).browser_download_url
    New-Item -Type Directory artifact;
    Set-Location ./artifact/
    Invoke-WebRequest $frontendDownloadUrl -Headers @{"X-GitHub-Api-Version" = "2022-11-28" } -OutFile frontend.zip
    Invoke-WebRequest $apiDownloadUrl -Headers @{"X-GitHub-Api-Version" = "2022-11-28" } -OutFile api.zip
    Invoke-WebRequest $deployDownloadUrl -Headers @{"X-GitHub-Api-Version" = "2022-11-28" } -OutFile deploy.ps1

    # deploy to webapp
    $secretProperties = Get-AzStaticWebAppSecret -Name $staticWebAppName -ResourceGroupName $resourceGroupName
    $token = $secretProperties.Property.Item("apiKey")
    $token.Substring(0,5)
    ./deploy.ps1 -Token $token -appBuildOutput ./frontend.zip -apiBuildOutput ./api.zip -apiFramework "dotnetisolated" -apiFrameworkVersion "7.0" -workingDir $pwd -Verbose
    '''
  }
}

output staticWebAppHost string = (empty(prNumber) || empty(branch) || empty(githubToken)) ? deployWebApp.properties.outputs.staticWebUrl : deployPrWebApp.properties.outputs.staticWebUrl
