namespace CZ.Azure.FileExchange.Api;

using System.Net;
using global::Azure.Storage.Blobs;
using global::Azure.Storage.Sas;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Azure.WebJobs.Extensions.OpenApi.Core.Attributes;
using Microsoft.Azure.WebJobs.Extensions.OpenApi.Core.Enums;
using Microsoft.Azure.WebJobs.Extensions.OpenApi.Core.Extensions;
using Microsoft.Extensions.Logging;
using Microsoft.OpenApi.Models;

public class GenerateSas
{
    private readonly ILogger<GenerateSas> logger;

    public GenerateSas(ILoggerFactory loggerFactory)
    {
        this.logger = loggerFactory.CreateLogger<GenerateSas>();
    }

    [OpenApiOperation(operationId: "greeting", tags: new[] { "sas" }, Summary = "Generate sas token", Description = "This generates a new sas token.", Visibility = OpenApiVisibilityType.Important)]
    [OpenApiParameter(name: "filecode", In = ParameterLocation.Query, Required = false, Type = typeof(string), Description = "The **code** parameter, that represent to get read access to stored files")]
    [OpenApiResponseWithBody(statusCode: HttpStatusCode.OK, contentType: "text/plain", bodyType: typeof(string), Description = "The OK response")]
    [Function("GenerateSas")]
    public async Task<HttpResponseData> Run(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = null)] HttpRequestData req,
            FunctionContext executionContext,
            string filecode)
    {
        this.logger.LogInformation("Start generating SaS");

        var blobservice = new BlobServiceClient(GetEnvironmentVariable("StorageConnectionString"));
        Uri? uri;
        BlobContainerClient? blobContainerClient;

        if (!string.IsNullOrWhiteSpace(filecode))
        {
            blobContainerClient = blobservice.GetBlobContainerClient(filecode);
            uri = this.GetServiceSasUriForContainer(blobContainerClient, BlobSasPermissions.Read | BlobSasPermissions.List);
        }
        else
        {
            var blobResponse = await blobservice.CreateBlobContainerAsync(Guid.NewGuid().ToString());
            _ = blobResponse.ThrowIfNullOrDefault();
            blobContainerClient = blobResponse.Value;
            uri = this.GetServiceSasUriForContainer(blobContainerClient);
        }
        if (uri == null)
        {
            this.logger.LogError("Failed to generate the Sas token");
            var responseBadRequest = req.CreateResponse(HttpStatusCode.BadRequest);
            responseBadRequest.Headers.Add("Content-Type", "text/plain; charset=utf-8");
            responseBadRequest.WriteString("Failed to greate SaS token to upload your files. Please try again.");
            return responseBadRequest;
        }

        var responseOK = req.CreateResponse(HttpStatusCode.OK);
        responseOK.Headers.Add("Content-Type", "text/plain; charset=utf-8");
        responseOK.WriteString(uri.ToString());
        return responseOK;
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

