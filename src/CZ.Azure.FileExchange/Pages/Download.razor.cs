namespace CZ.Azure.FileExchange.Pages;
using global::Azure.Storage.Blobs;
using global::Azure.Storage.Blobs.Models;

public partial class Download
{
    private string Code { get; set; } = string.Empty;
    private readonly List<BlobItem> blobs = new();
    private Uri? sasUrl;
    private async Task LoadFiles()
    {
        if (string.IsNullOrWhiteSpace(this.Code))
        {
            throw new ArgumentException("You must enter a code");
        }

        // until we don't find a solution to map a SAS uri to a code, we should always get a new uri. (something like a dictionary is maybe to overkill here)
        this.sasUrl = new Uri(await this.http.GetStringAsync($"api/GenerateSas?filecode={this.Code}"));

        if (this.sasUrl is null)
        {
            throw new ArgumentException("Sas uri is null");
        }
        var blobContainerClient = new BlobContainerClient(this.sasUrl);
        // Clear the list before using it again.
        this.blobs.Clear();
        await foreach (var singleBlob in blobContainerClient.GetBlobsAsync())
        {
            this.blobs.Add(singleBlob);
        }
    }

    private async Task<string> GetFileLink(string blobName, bool isArchived)
    {
        if (this.sasUrl is null)
        {
            throw new ArgumentException("Sas uri is null");
        }
        var parts = this.sasUrl.ToString().Split('?');
        return $"{parts[0]}/{blobName}?{parts[1]}";
    }

    /// <summary>
    /// This method helps to get things from the archival tier back to the hot tier
    /// </summary>
    /// <param name="blobName">The name of the blob</param>
    /// <returns></returns>
    private async Task StartRetrivalFromArchive(string blobName)
    {
        var blob = this.blobs.Single(b => b.Name.Equals(blobName, StringComparison.OrdinalIgnoreCase));

        if (blob.Properties.AccessTier != AccessTier.Archive)
        {
            this.logger.LogWarning($"User tried to retrieve a blob from archive, " +
            $"but the blob was not in the archive tier." +
            $"The blob: '{blob.Name}', tier: '{blob.Properties.AccessTier}'");
            /// TODO: make a user visible message that a not archived blob can't be retrieved
            return;
        }
        var blobContainerClient = new BlobContainerClient(this.sasUrl);
        var blobClient = blobContainerClient.GetBlobClient(blob.Name);
        var blobProperties = await blobClient.GetPropertiesAsync();
        if (
            string.Equals(blobProperties.Value.ArchiveStatus, "rehydrate-pending-to-hot", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(blobProperties.Value.ArchiveStatus, "rehydrate-pending-to-cool", StringComparison.OrdinalIgnoreCase)
        )
        {
            this.logger.LogWarning($"The blob '{blob.Name}' can't be retrieved because the " +
            $"status is {blobProperties.Value.ArchiveStatus}.");
            /// TODO: make a user visible message that the blob can't be double retrieved
            /// and return
        }
        await blobClient.SetAccessTierAsync(AccessTier.Hot);

        var blobListEntryLocation = this.blobs.FindIndex(b => b.Name.Equals(blobName, StringComparison.OrdinalIgnoreCase));
        if (blobListEntryLocation != -1)
        {
            var foundBlobs = 0;
            await foreach (var updatedBlob in blobContainerClient.GetBlobsAsync(prefix: blobName))
            {
                if (foundBlobs > 0)
                {
                    // TODO: something weird happend. We found for our blob we are looking for, more then one real blob.
                    this.logger.LogWarning($"The blob '{blobName}' exist more then ones. 🫨");
                }
                this.blobs[blobListEntryLocation] = updatedBlob;
            }
        }
        else
        {
            //TODO: some odd state happend. We change the state of the blob but we can't find it in our blobs list
            this.logger.LogWarning($"The blob '{blobName}' doesn't exist. 🫨");
        }



    }

    /// <summary>
    /// Formats from bytes to KB,MB,GB,TB
    /// stolen from: https://pastebin.com/x17NfmNJ
    /// </summary>
    /// <param name = "number">Bytes to format</param>
    /// <returns></returns>
    public static string AutoFileSize(long? number)
    {
        if (number == null)
        {
            return "0 KB";
        }

        var tmp = Convert.ToDouble(number.Value);
        var suffix = " B ";
        if (tmp > 1024)
        {
            tmp /= 1024;
            suffix = " KB";
        }

        if (tmp > 1024)
        {
            tmp /= 1024;
            suffix = " MB";
        }

        if (tmp > 1024)
        {
            tmp /= 1024;
            suffix = " GB";
        }

        if (tmp > 1024)
        {
            tmp /= 1024;
            suffix = " TB";
        }

        return $"{tmp:n}{suffix}";
    }
}
