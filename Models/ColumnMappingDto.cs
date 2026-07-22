namespace StajWebProjesi.Models
{
    public class ColumnMappingDto
    {
        public string? Table { get; set; }
        public string? TimestampColumn { get; set; }
        public string[]? SelectedColumns { get; set; }
    }
}
