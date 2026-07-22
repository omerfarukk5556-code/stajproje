namespace StajWebProjesi.Models;

public class BatchSelectionViewModel
{
    public List<BatchMasterItem> Batches { get; set; } = new();
    public List<HistTrendItem> HistTrends { get; set; } = new();
    public int? SelectedBatchId { get; set; }
    public string? Message { get; set; }
    public string? ErrorMessage { get; set; }
}

public class BatchMasterItem
{
    public int Id { get; set; }
    public string? BatchName { get; set; }
    public DateTime? BatchDate { get; set; }

    public string DisplayText =>
        !string.IsNullOrWhiteSpace(BatchName)
            ? $"{BatchName} ({BatchDate:dd.MM.yyyy HH:mm})"
            : $"Batch {Id} ({BatchDate:dd.MM.yyyy HH:mm})";
}

public class HistTrendItem
{
    public int Id { get; set; }
    public int BatchId { get; set; }
    public string? TrendValue { get; set; }
    public DateTime? CreatedAt { get; set; }

    public string DisplayText =>
        !string.IsNullOrWhiteSpace(TrendValue)
            ? TrendValue
            : $"Kayıt {Id}";
}
