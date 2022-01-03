[CmdletBinding()]
param (
    # your deployment token to deploy to azure static websites
    [Parameter(Mandatory = $true)]
    [string]
    $Token,
    # the path to your app build output
    [Parameter(Mandatory=$true)]
    [string]
    $appBuildOutput,
    # the path to your api build output
    [Parameter(Mandatory=$true)]
    [string]
    $apiBuildOutput,
    # Set a custom working directory.
    [Parameter(Mandatory=$false)]
    [string]
    $workingDir = "$pwd\temp\temp\"
)
New-Item -ItemType Directory -Force $workingDir;
Compress-Archive "$apiBuildOutput\*" -DestinationPath $workingDir/api.zip;
Compress-Archive "$appBuildOutput\*" -DestinationPath $workingDir/app.zip;
$apiHash = (Get-FileHash $workingDir/api.zip -Algorithm MD5).Hash;

$hostname = "content-am2.infrastructure.azurestaticapps.net";
$corelationId = (New-Guid).Guid.ToString();

$response = Invoke-RestMethod -Uri "https://$hostname/api/upload/validateapitoken?apiVersion=v1&deploymentCorrelationId=$corelationId" -Method Post -Headers @{
    "Authorization" = "token $token";
    "Content-Type"  = "application/json; charset=utf-8";
}

$siteUrl = $response.response.siteUrl;
Write-Verbose "The site to be update is: $siteUrl";

$metaDeployInforamtion = @{
    EventInfo   = $null;
    PollingInfo = $null;
    UploadInfo  = @{
        # this must be always different. Else it wouldn't upload the api
        ApiContentHash          = "$apiHash";
        ApiSizeInBytes          = (Get-Item $workingDir/api.zip).Length;
        AppFileCount            = (Get-ChildItem $appPath -Recurse -File | Measure-Object).Count;
        AppSizeInBytes          = (Get-Item $workingDir/app.zip).Length;
        ConfiguredRoles         = @();
        DefaultFileType         = "index.html";
        # this can be anything
        DeploymentProvider      = "myown";
        FunctionLanguage        = "dotnet";
        FunctionLanguageVersion = "6.0.0";
        HasFunctions            = $true;
        HasRoutes               = $false;
        Status                  = "RequestingUpload";
    }
}
$metaDeployInforamtionBody = ConvertTo-Json -InputObject $metaDeployInforamtion;

$response = Invoke-RestMethod -Uri "https://$hostname/api/upload/request?apiVersion=v1&deploymentCorrelationId=$corelationId" -Method Post -Headers @{
    "Authorization" = "token $token";
    "Content-Type"  = "application/json; charset=utf-8";
} -Body $metaDeployInforamtionBody;

Write-Verbose "API deploy URL is: $($response.response.packageUris.api).";
Write-Verbose "APP deploy URL is: $($response.response.packageUris.app).";
$metaDeployInforamtion.PollingInfo = @{
    DefaultHostname     = $response.response.pollingInfo.defaultHostname;
    StageSiteIdentifier = $response.response.pollingInfo.stageSiteIdentifier;
    Version             = $response.response.pollingInfo.version;
};
$metaDeployInforamtionBody = ConvertTo-Json -InputObject $metaDeployInforamtion;
$metaDeployInforamtionBody;
if ($null -ne $response.response.packageUris.api -and
    [string]::IsNullOrWhiteSpace($response.response.packageUris.api) -eq $false) {
    $blobGuid = (New-Guid).Guid.ToString();
    Invoke-WebRequest -Method Put -Uri $response.response.packageUris.api -InFile $workingDir/api.zip -Headers @{
        "x-ms-blob-type"                = "BlockBlob";
        "x-ms-client-request-id"        = "$blobGuid";
        "x-ms-return-client-request-id" = "true";
        "x-ms-version"                  = "2020-08-04"
    } -ContentType "application/octet-stream";
    Write-Verbose "uploading api is done";
}
else {
    Write-Verbose "skipping the upload of the api.";
}
if ($null -ne $response.response.packageUris.app -and
    [string]::IsNullOrWhiteSpace($response.response.packageUris.app) -eq $false) {
    $blobGuid = (New-Guid).Guid.ToString();
    Invoke-WebRequest -Method Put -Uri $response.response.packageUris.app -InFile $workingDir/app.zip -Headers @{
        "x-ms-blob-type"                = "BlockBlob";
        "x-ms-client-request-id"        = "$blobGuid";
        "x-ms-return-client-request-id" = "true";
        "x-ms-version"                  = "2020-08-04"
    } -ContentType "application/octet-stream";
    Write-Verbose "uploading app is done";
}
else {
    Write-Verbose "skipping the upload of the app.";
}

$metaDeployInforamtion.UploadInfo.Status = "Succeeded";
Write-Verbose "Set upload status to succeeded";
$metaDeployInforamtionBody = ConvertTo-Json -InputObject $metaDeployInforamtion;
$response = Invoke-RestMethod -Uri "https://$hostname/api/upload/updatestatus?apiVersion=v1&deploymentCorrelationId=$corelationId" -Method Post -Headers @{
    "Authorization" = "token $token";
    "Content-Type"  = "application/json; charset=utf-8";
} -Body $metaDeployInforamtionBody;
Write-Verbose "Deployment started?: $($response.isSuccessStatusCode), $($response.response)";

$checkstatusBody = ConvertTo-Json -InputObject $metaDeployInforamtion.PollingInfo;
while (
    $null -eq $response.response -or
    $response.response.deploymentStatus -like "InProgress"
) {
    $response = Invoke-RestMethod -Uri "https://$hostname/api/upload/checkstatus?apiVersion=v1&deploymentCorrelationId=$corelationId" -Method Post -Headers @{
        "Authorization" = "token $token";
        "Content-Type"  = "application/json; charset=utf-8";
    } -Body $checkstatusBody;
    $response;
    Start-Sleep 2;
}

Remove-Item -Recurse -Force $workingDir;

