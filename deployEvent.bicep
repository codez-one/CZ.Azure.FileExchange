param location string  = resourceGroup().location
param baseUrl string
param prNumber string = ''
param storageAccountName string = uniqueString(resourceGroup().id, '7f358957-c1be-48ad-8902-808564e0556f')

var eventName = !empty(prNumber) ? '${prNumber}-back-from-archive' : 'back-from-archive'
var storageAccountId = resourceId(resourceGroup().name, 'Microsoft.Storage/storageAccounts' , storageAccountName)

resource eventTopic 'Microsoft.EventGrid/systemTopics@2022-06-15' = {
  name: 'storageEvents'
  location: location
  properties: {
    source: storageAccountId
    topicType: 'Microsoft.Storage.StorageAccounts'
  }
}

resource archiveEvent 'Microsoft.EventGrid/eventSubscriptions@2022-06-15' = {
  name: eventName
  scope: eventTopic
  properties: {
    destination: {
      endpointType: 'WebHook'
      properties: {
        endpointUrl: '${baseUrl}/api/AddMetadata'
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
