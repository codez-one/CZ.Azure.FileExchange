namespace CZ.Azure.FileExchange.Api
{
    using System;
    using System.Net;
    using Microsoft.Azure.Functions.Worker;
    using Microsoft.Azure.WebJobs.Extensions.OpenApi.Core.Attributes;
    using Microsoft.Extensions.Logging;
    using Microsoft.OpenApi.Models;
    using global::Azure.Messaging.EventGrid;
    using Microsoft.Azure.Functions.Worker.Http;
    using static System.Runtime.InteropServices.JavaScript.JSType;
    using global::Azure.Messaging.EventGrid.SystemEvents;
    using global::Azure.Storage.Blobs;
    using System.Globalization;

    public class AddMetadata
    {
        private readonly ILogger _logger;
        private readonly HttpClient httpClient;
        private const string blobCreated = "Microsoft.Storage.BlobCreated";
        private const string copyBlob = "CopyBlob";
        private const string blobChanged = "Microsoft.Storage.BlobTierChanged";
        private const string setBlobTier = "SetBlobTier";
        private const string azureValidation = "Microsoft.EventGrid.SubscriptionValidationEvent";


        public AddMetadata(ILoggerFactory loggerFactory, HttpClient httpClient)
        {
            _logger = loggerFactory.CreateLogger<AddMetadata>();
            this.httpClient = httpClient;
        }

        [Function("AddMetadata")]
        [OpenApiOperation(operationId: "Run")]
        [OpenApiRequestBody("application/json", typeof(IEnumerable<EventGridEvent>))]
        [OpenApiResponseWithBody(statusCode: HttpStatusCode.OK, contentType: "text/plain", bodyType: typeof(string), Description = "The OK response")]
        public async Task<HttpResponseData> Run([HttpTrigger(AuthorizationLevel.Anonymous, "PUT", "POST", Route = null)] HttpRequestData req)
        {
            _logger.LogInformation($"An event happend that maybe is a blob hydration from archive");
            var eventsRaw = await BinaryData.FromStreamAsync(req.Body);
            _logger.LogInformation($"received events: {eventsRaw}");
            var events = EventGridEvent.ParseMany(eventsRaw);
            var relevantChangeTierEvents = events.Where(e =>
                e.EventType == blobChanged &&
                e.Data.ToObjectFromJson<BlobTierChangeEvent>().api == setBlobTier
                );

            var relevantValidationEvents = events.Where(e =>
                e.EventType == azureValidation
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
                            _logger.LogInformation($"Got SubscriptionValidation event data, validation code: {subscriptionValidationEventData.ValidationCode}, topic: {e.Topic}");
                            _logger.LogInformation("The validation of the webhook was successful");
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
}
