using Microsoft.AspNetCore.Components.Forms;
using global::Azure.Storage.Blobs;
using global::Azure.Storage.Blobs.Models;
using Microsoft.AspNetCore.Components;

namespace CZ.Azure.FileExchange.Pages;

public partial class Index
{
    [Inject]
    protected HttpClient http { get; set; } = default!;

    List<File> files = new();
    Uri? SasUrl;
    private string inputFileId = Guid.NewGuid().ToString();
    private bool isDragHover;

    public string? SasId => SasUrl?.AbsolutePath?.Replace("/", "");

    private void LoadFiles(InputFileChangeEventArgs e)
    {
        foreach (var file in e.GetMultipleFiles())
        {
            var fileModel = new File()
            {Name = file.Name, BrowserFile = file};
            files.Add(fileModel);
        }

        // this magic is needed to clear the imput. If this is not done a deleted file can not selected again.
        // Solution found here: https://stackoverflow.com/a/70877124/6526640
        this.inputFileId = Guid.NewGuid().ToString();
    }

    private void DragEnter(){
        this.isDragHover = true;
    }

    private void DragLeave(){
        this.isDragHover = false;
    }

    private async Task StartUpload()
    {
        if (SasUrl == null)
        {
            var result = await http.GetStringAsync("api/GenerateSas");
            SasUrl = new Uri(result);
        }

        if (SasUrl is null)
        {
            throw new Exception("Sas uri is null");
        }

        var blobContainerClient = new BlobContainerClient(SasUrl);
        Parallel.ForEach(files.Where(f => f.ProcessedSize != f.BrowserFile.Size), async f =>
        {
            var blobClient = blobContainerClient.GetBlobClient(f.BrowserFile.Name);
            await blobClient.UploadAsync(f.BrowserFile.OpenReadStream(long.MaxValue), new BlobUploadOptions()
            {ProgressHandler = new ProgressHandler(this, f)});
        });
    }

    private Task DeleteFile(File file){
        files.Remove(file);
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
            file.ProcessedSize = value;
            pageRef.StateHasChanged();
        }
    }
}
