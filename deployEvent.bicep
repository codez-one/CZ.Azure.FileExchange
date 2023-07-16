param location string  = resourceGroup().location
param hostname string
param storageAccountName string = uniqueString(resourceGroup().id, '7f358957-c1be-48ad-8902-808564e0556f')

var storageAccountId = resourceId(resourceGroup().name, 'Microsoft.Storage/storageAccounts' , storageAccountName)

resource eventTopic 'Microsoft.EventGrid/systemTopics@2023-06-01-preview' = {
  name: 'storageEvents'
  location: location
  properties: {
    source: storageAccountId
    topicType: 'Microsoft.Storage.StorageAccounts'
  }
}

resource archiveEvent 'Microsoft.EventGrid/eventSubscriptions@2023-06-01-preview' = {
  name: 'back-from-archive'
  scope: eventTopic
  properties: {
    destination: {
      endpointType: 'WebHook'
      properties: {
        endpointUrl: 'https://${hostname}/api/AddMetadata'
      }
    }
    filter: {
      includedEventTypes: [
        'Microsoft.Storage.BlobCreated'
        'Microsoft.Storage.BlobTierChanged'
      ]
      enableAdvancedFilteringOnArrays: true
    }
    eventDeliverySchema: 'EventGridSchema'
    retryPolicy: {
      maxDeliveryAttempts: 30
      eventTimeToLiveInMinutes: 1440
    }
  }
}
