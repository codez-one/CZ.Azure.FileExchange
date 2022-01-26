[CmdletBinding()]
param (
    # your deployment token to deploy to azure static websites
    [Parameter(Mandatory = $true)]
    [string]
    $Token,
    # the path to your app build output
    [Parameter(Mandatory = $true)]
    [string]
    $appBuildOutput,
    # the path to your api build output
    [Parameter(Mandatory = $true)]
    [string]
    $apiBuildOutput,
    # Set a custom working directory.
    [Parameter(Mandatory = $false)]
    [string]
    $workingDir = "$pwd\temp\temp\",
    # Set a branch name that is used in the deciption of the envrionment
    [Parameter(Mandatory = $false)]
    [string]
    $branchName = $null,
    # set the environment name. normaly it should be equal to the PR Id
    [Parameter(Mandatory = $false)]
    [string]
    $envrionmentName = $null,
    # the pullrequest Title
    [Parameter(Mandatory = $false)]
    [string]
    $pullrequestTitle = $null,
    # delete stage if set
    [Parameter(Mandatory = $false)]
    [switch]
    $Delete
)
$EventInfo = $null;
if ($false -eq [string]::IsNullOrWhiteSpace($pullrequestTitle) -or 
    $false -eq [string]::IsNullOrWhiteSpace($envrionmentName) -or 
    $false -eq [string]::IsNullOrWhiteSpace($branchName)
) {
    $EventInfo = @{
        BaseBranch       = $branchName
        HeadBranch       = $branchName
        PullRequestId    = $envrionmentName
        PullRequestTitle = $pullrequestTitle
        IsPullRequest    = $false -eq [string]::IsNullOrWhiteSpace($pullrequestTitle) -or $false -eq [string]::IsNullOrWhiteSpace($envrionmentName) ? $true : $false
    }
}

$hostname = "content-am2.infrastructure.azurestaticapps.net";
$corelationId = (New-Guid).Guid.ToString();

$response = Invoke-RestMethod -Uri "https://$hostname/api/upload/validateapitoken?apiVersion=v1&deploymentCorrelationId=$corelationId" -Method Post -Headers @{
    "Authorization" = "token $token";
    "Content-Type"  = "application/json; charset=utf-8";
} -Body $EventInfo;

if ($response.isSuccessStatusCode -eq $false) {
    Write-Verbose "Start bruteforce on hostname, because the default hostname don't know the token."
    # latest research shows, that there are diffrent deployment host. Up to three per region
    # we now just start brutforce to find the host that accepts the token
    $instanceIds = 1..3;
    foreach ($instanceId in $instanceIds) {
        $hostname = "content-am2.infrastructure.$instanceId.azurestaticapps.net";
        Write-Verbose "Test hostname '$hostname' with id $instanceId";
        $response = Invoke-RestMethod -Uri "https://$hostname/api/upload/validateapitoken?apiVersion=v1&deploymentCorrelationId=$corelationId" -Method Post -Headers @{
            "Authorization" = "token $token";
            "Content-Type"  = "application/json; charset=utf-8";
        }  -Body $EventInfo;
        if ($response.isSuccessStatusCode -eq $true) {
            Write-Verbose "Brutforce on hostname was sucessfull.";
            break;
        }
        if ($instanceId -eq 3) {
            Write-Error "can't connect to the static website. Check the token";
            break;
        }
    }
}

if($Delete){
    $response = Invoke-RestMethod -Uri "https://$hostname/api/pullrequest/close?apiVersion=v1&deploymentCorrelationId=$corelationId" -Method Post -Headers @{
        "Authorization" = "token $token";
        "Content-Type"  = "application/json; charset=utf-8";
    }  -Body ($EventInfo | ConvertTo-Json);
    if($response.isSuccessStatusCode -eq $false){
        Write-Error "Deleting PR wasn't successfull";
        Write-Verbose $response;
    }
    break;
}

New-Item -ItemType Directory -Force $workingDir;
Compress-Archive "$apiBuildOutput\*" -DestinationPath $workingDir/api.zip;
Compress-Archive "$appBuildOutput\*" -DestinationPath $workingDir/app.zip;
$apiHash = (Get-FileHash $workingDir/api.zip -Algorithm MD5).Hash;





$siteUrl = $response.response.siteUrl;
Write-Verbose "The site to be update is: $siteUrl";



$metaDeployInforamtion = @{
    EventInfo   = $EventInfo;
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
$response.response.siteUrl;
# echo "::set-output name=pr-title::$(echo $title)"
"::set-output name=siteurl::$($response.response.siteUrl)";
echo "::set-output name=siteurl::$($response.response.siteUrl)";
Write-Output "::set-output name=SiteUrl::$($response.response.siteUrl)";