namespace CZ.Azure.FileExchange.Pages;

using Microsoft.AspNetCore.Components.Forms;
using global::Azure.Storage.Blobs;
using global::Azure.Storage.Blobs.Models;
using Microsoft.AspNetCore.Components;

public partial class Index
{
    [Inject]
    private HttpClient Http { get; set; } = default!;

    private readonly List<File> files = new();
    private Uri? sasUrl;
    private readonly IList<string> fileInputs = new List<string>() { Guid.NewGuid().ToString() };
    private bool isDragHover;

    public string? SasId => this.sasUrl?.AbsolutePath?.Replace("/", "");


    private void LoadFiles(InputFileChangeEventArgs e)
    {
        foreach (var file in e.GetMultipleFiles(maximumFileCount: int.MaxValue))
        {
            var fileModel = new File(file.Name, file);
            this.files.Add(fileModel);
        }

        // this magic is needed to ensure all ever selected files will be uploaded.
        this.fileInputs.Add(Guid.NewGuid().ToString());
    }

    private void DragEnter() => this.isDragHover = true;

    private void DragLeave() => this.isDragHover = false;

    private async Task StartUpload()
    {
        if (this.sasUrl == null)
        {
            var result = await this.Http.GetStringAsync("api/GenerateSas");
            this.sasUrl = new Uri(result);
        }

        if (this.sasUrl is null)
        {
            throw new ArgumentNullException("Sas uri is null");
        }

        var blobContainerClient = new BlobContainerClient(this.sasUrl);
        var throttling = new SemaphoreSlim(4, 4);
        var fileTasks = this.files
            .Where(f => f.ProcessedSize != f.BrowserFile.Size)
            .Select(async f =>
            {
                try
                {
                    await throttling.WaitAsync();
                    var blobClient = blobContainerClient.GetBlobClient(f.BrowserFile.Name);
                    using var filestream = f.BrowserFile.OpenReadStream(long.MaxValue);
                    _ = await blobClient.UploadAsync(
                        filestream,
                        new BlobUploadOptions() { ProgressHandler = new ProgressHandler(this, f) }
                    );
                }
                finally
                {
                    _ = throttling.Release();
                }

            });
        await Task.WhenAll(fileTasks);
    }

    private Task DeleteFile(File file)
    {
        _ = this.files.Remove(file);
        return Task.CompletedTask;
    }

    private sealed class File
    {
        public File(string name, IBrowserFile browserFile, long processedSize = 0)
        {
            this.Name = name;
            this.BrowserFile = browserFile;
            this.ProcessedSize = processedSize;
        }
        public string Name { get; set; }

        public IBrowserFile BrowserFile { get; set; }

        public long ProcessedSize { get; set; }
    }

    private sealed class ProgressHandler : IProgress<long>
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
