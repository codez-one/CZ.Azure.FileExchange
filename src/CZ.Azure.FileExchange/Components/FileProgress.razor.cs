namespace CZ.Azure.FileExchange.Components;

using Microsoft.AspNetCore.Components;

public partial class FileProgress
{
    [Parameter]
    public string Name { get; set; }

    [Parameter]
    public long ProcessedSize { get; set; }

    [Parameter]
    public long Size { get; set; }

    private UploadState State { get; set; } = UploadState.NotStarted;
    public int Progress
    {
        get
        {
            var percent = decimal.Divide(this.ProcessedSize, this.Size) * 100;
            percent = decimal.Round(percent);
            if (percent is < 100 and > 0)
            {
                this.State = UploadState.InProgrogress;
            }

            if (percent >= 100)
            {
                this.State = UploadState.Succeeded;
            }

            return Convert.ToInt32(percent);
        }
    }

    private enum UploadState
    {
        NotStarted,
        InProgrogress,
        Succeeded,
        Failed
    }
}
