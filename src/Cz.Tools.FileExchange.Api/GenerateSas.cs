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
using Azure.Storage.Blobs;
using Azure.Storage.Sas;
using Microsoft.Azure.WebJobs.Extensions.OpenApi.Core.Extensions;
using System.Net.Http;

namespace Cz.Tools.FileExchange.Api
{
    public class GenerateSas
    {
        private readonly ILogger<GenerateSas> _logger;

        public GenerateSas(ILogger<GenerateSas> log)
        {
            _logger = log;
        }

        [FunctionName("GenerateSas")]
        [OpenApiOperation(operationId: "Run")]
        [OpenApiParameter(name: "filecode", In = ParameterLocation.Query, Required = false, Type = typeof(string), Description = "The **code** parameter, that represent to get read access to stored files")]
        [OpenApiResponseWithBody(statusCode: HttpStatusCode.OK, contentType: "text/plain", bodyType: typeof(string), Description = "The OK response")]
        public async Task<IActionResult> Run(
            [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = null)] HttpRequest req)
        {
            _logger.LogInformation("Start generating SaS");

            var blobservice = new BlobServiceClient(GetEnvironmentVariable("StorageConnectionString"));
            BlobContainerClient? blobContainerClient = null;
            if(req.Query.TryGetValue("filecode", out var code))
            {
                blobContainerClient = blobservice.GetBlobContainerClient(code);
            }
            else
            {
                var response = await blobservice.CreateBlobContainerAsync(Guid.NewGuid().ToString());
                response.ThrowIfNullOrDefault();
                blobContainerClient = response.Value;
            }
            
            var uri = GetServiceSasUriForContainer(blobContainerClient);
            if (uri == null)
            {
                _logger.LogError("Failed to generate the Sas token");
                new BadRequestObjectResult(new StringContent("Failed to greate SaS token to upload your files. Please try again."));
            }

            return new OkObjectResult(uri.ToString());
        }

        private static string GetEnvironmentVariable(string name)
        {
            return System.Environment.GetEnvironmentVariable(name, EnvironmentVariableTarget.Process);
        }
        private Uri GetServiceSasUriForContainer(
            BlobContainerClient containerClient,
            BlobSasPermissions permission = BlobSasPermissions.Write | BlobSasPermissions.Read | BlobSasPermissions.List,
            string storedPolicyName = null
        )
        {
            // Check whether this BlobContainerClient object has been authorized with Shared Key.
            if (containerClient.CanGenerateSasUri)
            {
                // Create a SAS token that's valid for one hour.
                BlobSasBuilder sasBuilder = new BlobSasBuilder()
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

                Uri sasUri = containerClient.GenerateSasUri(sasBuilder);
                _logger.LogInformation("SAS URI for blob container is: {0}", sasUri);

                return sasUri;
            }
            else
            {
                _logger.LogError(@"BlobContainerClient must be authorized with Shared Key 
                          credentials to create a service SAS.");
                return null;
            }
        }
    }
}

