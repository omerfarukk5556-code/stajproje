namespace StajWebProjesi.Models;

public class DbConnectionInfo
{
    public string? Provider { get; set; }

    // For SQL Server
    public string? Server { get; set; }
    public string? Database { get; set; }
    // "Windows" or "SqlServer"
    public string Authentication { get; set; } = "Windows";

    // Credentials for SQL Server authentication
    public string? Username { get; set; }
    public string? Password { get; set; }

    // Optional full connection string (overrides other fields if provided)
    public string? ConnectionString { get; set; }
}
