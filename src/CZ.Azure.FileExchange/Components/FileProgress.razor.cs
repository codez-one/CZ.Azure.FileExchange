using Microsoft.AspNetCore.Components;

namespace CZ.Azure.FileExchange.Components;

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
            decimal percent = Decimal.Divide(ProcessedSize, Size) * 100;
            percent = Decimal.Round(percent);
            if (percent < 100 && percent > 0)
            {
                State = UploadState.InProgrogress;
            }

            if (percent >= 100)
            {
                State = UploadState.Succeeded;
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
