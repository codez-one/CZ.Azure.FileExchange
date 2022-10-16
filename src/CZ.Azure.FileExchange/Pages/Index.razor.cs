namespace CZ.Azure.FileExchange.Pages;

using Microsoft.AspNetCore.Components.Forms;
using global::Azure.Storage.Blobs;
using global::Azure.Storage.Blobs.Models;
using Microsoft.AspNetCore.Components;

public partial class Index
{
    [Inject]
    private HttpClient http { get; set; }

    List<File> files = new();
    Uri? SasUrl;
    private readonly IList<string> fileInputs = new List<string>() { Guid.NewGuid().ToString() };
    private bool isDragHover;

    public string? SasId => this.SasUrl?.AbsolutePath?.Replace("/", "");


    private void LoadFiles(InputFileChangeEventArgs e)
    {
        foreach (var file in e.GetMultipleFiles(maximumFileCount: int.MaxValue))
        {
            var fileModel = new File()
            {
                Name = file.Name,
                BrowserFile = file
            };
            this.files.Add(fileModel);
        }

        // this magic is needed to ensure all ever selected files will be uploaded.
        this.fileInputs.Add(Guid.NewGuid().ToString());
    }

    private void DragEnter() => this.isDragHover = true;

    private void DragLeave() => this.isDragHover = false;

    private async Task StartUpload()
    {
        if (this.SasUrl == null)
        {
            var result = await this.http.GetStringAsync("api/GenerateSas");
            this.SasUrl = new Uri(result);
        }

        if (this.SasUrl is null)
        {
            throw new ArgumentNullException("Sas uri is null");
        }

        var blobContainerClient = new BlobContainerClient(this.SasUrl);
        _ = Parallel.ForEach(
            this.files.Where(
                f => f.ProcessedSize != f.BrowserFile.Size
            ), new ParallelOptions(){
                // this is here to avoid the exploding of the browser APIs
                // if you build up a to big queue for webrequest, for some reason,
                // some browser don't like it.
                // so we limit this here to 4.
                MaxDegreeOfParallelism = 4
            }, async f =>
            {
                var blobClient = blobContainerClient.GetBlobClient(f.BrowserFile.Name);
                _ = await blobClient.UploadAsync(f.BrowserFile.OpenReadStream(long.MaxValue), new BlobUploadOptions()
                { ProgressHandler = new ProgressHandler(this, f) });
            }
        );
    }

    private Task DeleteFile(File file)
    {
        _ = this.files.Remove(file);
        return Task.CompletedTask;
    }

    class File
    {
        public string Name { get; set; }

        public IBrowserFile BrowserFile { get; set; }

        public long ProcessedSize { get; set; }
    }

    private class ProgressHandler : IProgress<long>
    {
        private readonly Index pageRef;
        private readonly File file;

        public ProgressHandler(Index pageRef, File file)
        {
            this.pageRef = pageRef;
            this.file = file;
        }

        void IProgress<long>.Report(long value)
        {
            this.file.ProcessedSize = value;
            this.pageRef.StateHasChanged();
        }
    }
}
