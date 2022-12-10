namespace CZ.Azure.FileExchange.Api;

using System;
using System.Net;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Extensions.Http;
using Microsoft.Azure.WebJobs.Extensions.OpenApi.Core.Attributes;
using Microsoft.Extensions.Logging;
using Microsoft.OpenApi.Models;
using global::Azure.Storage.Blobs;
using global::Azure.Storage.Sas;
using Microsoft.Azure.WebJobs.Extensions.OpenApi.Core.Extensions;
using System.Net.Http;

public class GenerateSas
{
    private readonly ILogger<GenerateSas> logger;

    public GenerateSas(ILogger<GenerateSas> log) =>
        this.logger = log;

    [FunctionName("GenerateSas")]
    [OpenApiOperation(operationId: "Run")]
    [OpenApiParameter(name: "filecode", In = ParameterLocation.Query, Required = false, Type = typeof(string), Description = "The **code** parameter, that represent to get read access to stored files")]
    [OpenApiResponseWithBody(statusCode: HttpStatusCode.OK, contentType: "text/plain", bodyType: typeof(string), Description = "The OK response")]
    public async Task<IActionResult> Run(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = null)] HttpRequest req)
    {
        this.logger.LogInformation("Start generating SaS");

        var blobservice = new BlobServiceClient(GetEnvironmentVariable("StorageConnectionString"));
        Uri? uri;
        BlobContainerClient? blobContainerClient;
        if (req.Query.TryGetValue("filecode", out var code))
        {
            blobContainerClient = blobservice.GetBlobContainerClient(code);
            uri = this.GetServiceSasUriForContainer(blobContainerClient, BlobSasPermissions.Read | BlobSasPermissions.List);
        }
        else
        {
            var response = await blobservice.CreateBlobContainerAsync(Guid.NewGuid().ToString());
            _ = response.ThrowIfNullOrDefault();
            blobContainerClient = response.Value;
            uri = this.GetServiceSasUriForContainer(blobContainerClient);
        }
        if (uri == null)
        {
            this.logger.LogError("Failed to generate the Sas token");
            return new BadRequestObjectResult(new StringContent("Failed to greate SaS token to upload your files. Please try again."));
        }

        return new OkObjectResult(uri.ToString());
    }

    private static string GetEnvironmentVariable(string name) =>
        Environment.GetEnvironmentVariable(name, EnvironmentVariableTarget.Process) ??
        throw new ArgumentException($"The setting for {name} is missing.");
    private Uri? GetServiceSasUriForContainer(
        BlobContainerClient containerClient,
        BlobSasPermissions permission = BlobSasPermissions.Write | BlobSasPermissions.Read | BlobSasPermissions.List,
        string? storedPolicyName = null
    )
    {
        // Check whether this BlobContainerClient object has been authorized with Shared Key.
        if (containerClient.CanGenerateSasUri)
        {
            // Create a SAS token that's valid for one hour.
            var sasBuilder = new BlobSasBuilder()
            {
                BlobContainerName = containerClient.Name,
                Resource = "c"
            };

            if (storedPolicyName == null)
            {
                sasBuilder.ExpiresOn = DateTimeOffset.UtcNow.AddHours(1);
                sasBuilder.SetPermissions(permission);
            }
            else
            {
                sasBuilder.Identifier = storedPolicyName;
            }

            var sasUri = containerClient.GenerateSasUri(sasBuilder);
            this.logger.LogInformation("SAS URI for blob container is: {0}", sasUri);

            return sasUri;
        }
        else
        {
            this.logger.LogError(@"BlobContainerClient must be authorized with Shared Key 
                          credentials to create a service SAS.");
            return null;
        }
    }
}

