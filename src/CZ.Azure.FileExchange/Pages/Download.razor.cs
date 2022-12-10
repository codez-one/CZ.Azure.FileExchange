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

        if (this.sasUrl == null)
        {
            this.sasUrl = new Uri(await this.http.GetStringAsync($"api/GenerateSas?filecode={this.Code}"));
        }

        if (this.sasUrl is null)
        {
            throw new ArgumentException("Sas uri is null");
        }

        var blobContainerClient = new BlobContainerClient(this.sasUrl);
        await foreach (var singleBlob in blobContainerClient.GetBlobsAsync())
        {
            this.blobs.Add(singleBlob);
        }
    }

    private string GetFileLink(string blobName)
    {
        if (this.sasUrl is null)
        {
            throw new ArgumentException("Sas uri is null");
        }

        var parts = this.sasUrl.ToString().Split('?');
        return $"{parts[0]}/{blobName}?{parts[1]}";
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
