using global::Azure.Storage.Blobs;
using global::Azure.Storage.Blobs.Models;

namespace CZ.Azure.FileExchange.Pages;

public partial class Download
{
    private string Code { get; set; } = string.Empty;
    private List<BlobItem> blobs = new();
    Uri? SasUrl;
    private async Task LoadFiles()
    {
        if (string.IsNullOrWhiteSpace(Code))
        {
            throw new Exception("You must enter a code");
        }

        if (SasUrl == null)
        {
            SasUrl = new Uri(await http.GetStringAsync($"api/GenerateSas?filecode={Code}"));
        }

        if (SasUrl is null)
        {
            throw new Exception("Sas uri is null");
        }

        var blobContainerClient = new BlobContainerClient(SasUrl);
        await foreach (var singleBlob in blobContainerClient.GetBlobsAsync())
        {
            blobs.Add(singleBlob);
        }
    }

    private string GetFileLink(string blobName)
    {
        if (SasUrl is null)
        {
            throw new Exception("Sas uri is null");
        }

        var parts = SasUrl.ToString().Split('?');
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

        double tmp = System.Convert.ToDouble(number.Value);
        string suffix = " B ";
        if (tmp > 1024)
        {
            tmp = tmp / 1024;
            suffix = " KB";
        }

        if (tmp > 1024)
        {
            tmp = tmp / 1024;
            suffix = " MB";
        }

        if (tmp > 1024)
        {
            tmp = tmp / 1024;
            suffix = " GB";
        }

        if (tmp > 1024)
        {
            tmp = tmp / 1024;
            suffix = " TB";
        }

        return tmp.ToString("n") + suffix;
    }
}
