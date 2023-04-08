namespace CZ.Azure.FileExchange.Api;

using System;
using System.Net;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.WebJobs.Extensions.OpenApi.Core.Attributes;
using Microsoft.Extensions.Logging;
using Microsoft.OpenApi.Models;
using global::Azure.Messaging.EventGrid;
using Microsoft.Azure.Functions.Worker.Http;
using global::Azure.Messaging.EventGrid.SystemEvents;
using global::Azure.Storage.Blobs;
using System.Globalization;

public class AddMetadata
{
    private readonly ILogger logger;
    private const string BlobChanged = "Microsoft.Storage.BlobTierChanged";
    private const string SetBlobTier = "SetBlobTier";
    private const string AzureValidation = "Microsoft.EventGrid.SubscriptionValidationEvent";


    public AddMetadata(ILoggerFactory loggerFactory) => this.logger = loggerFactory.CreateLogger<AddMetadata>();

    [Function("AddMetadata")]
    [OpenApiOperation(operationId: "Run")]
    [OpenApiRequestBody("application/json", typeof(IEnumerable<EventGridEvent>))]
    [OpenApiResponseWithBody(statusCode: HttpStatusCode.OK, contentType: "text/plain", bodyType: typeof(string), Description = "The OK response")]
    public async Task<HttpResponseData> Run(
        [HttpTrigger(AuthorizationLevel.Anonymous, "PUT", "POST", Route = null)] HttpRequestData req)
    {
        this.logger.LogInformation($"An event happend that maybe is a blob hydration from archive");
        var eventsRaw = await BinaryData.FromStreamAsync(req.Body);
        this.logger.LogInformation($"received events: {eventsRaw}");
        var events = EventGridEvent.ParseMany(eventsRaw);
        var relevantChangeTierEvents = events.Where(e =>
            e.EventType == BlobChanged &&
            e.Data.ToObjectFromJson<BlobTierChangeEvent>().api == SetBlobTier
            );

        var relevantValidationEvents = events.Where(e =>
            e.EventType == AzureValidation
            );
        if (relevantChangeTierEvents.Any())
        {
            var blobService = new BlobServiceClient(GetEnvironmentVariable("StorageConnectionString"));
            foreach (var tierChangedEvent in relevantChangeTierEvents)
            {
                var data = tierChangedEvent.Data.ToObjectFromJson<BlobTierChangeEvent>();
                var blobUri = new Uri(data.url);
                var containerName = blobUri.Segments.Skip(1).First()[..^1];
                var containerClient = blobService.GetBlobContainerClient(containerName);
                var blobClient = containerClient.GetBlobClient(blobUri.Segments.Last());
                await blobClient.SetMetadataAsync(new Dictionary<string, string>() {
                     // That is important to change the 'x-ms-last-access-time'
                    { "lastTimeRetrieved", tierChangedEvent.EventTime.ToString(CultureInfo.CurrentCulture)}
                });
            }
        }


        if (relevantValidationEvents.Any())
        {
            foreach (var e in relevantValidationEvents)
            {
                if (e.TryGetSystemEventData(out var data))
                {
                    if (data is SubscriptionValidationEventData subscriptionValidationEventData)
                    {
                        this.logger.LogInformation($"Got SubscriptionValidation event data, validation code: {subscriptionValidationEventData.ValidationCode}, topic: {e.Topic}");
                        this.logger.LogInformation("The validation of the webhook was successful");
                        var responseData = new
                        {
                            ValidationResponse = subscriptionValidationEventData.ValidationCode
                        };
                        var response = req.CreateResponse(HttpStatusCode.OK);
                        await response.WriteAsJsonAsync(responseData);
                        return response;
                    }
                }
            }
        }

        return req.CreateResponse(HttpStatusCode.OK);

    }

    private static string GetEnvironmentVariable(string name) =>
    Environment.GetEnvironmentVariable(name, EnvironmentVariableTarget.Process) ??
    throw new ArgumentException($"The setting for {name} is missing.");


    public class BlobTierChangeEvent
    {
        public string api { get; set; }
        public string requestId { get; set; }
        public string eTag { get; set; }
        public string contentType { get; set; }
        public int contentLength { get; set; }
        public string blobType { get; set; }
        public string url { get; set; }
        public string sequencer { get; set; }
        public Storagediagnostics storageDiagnostics { get; set; }
    }

    public class Storagediagnostics
    {
        public string batchId { get; set; }
    }

}
