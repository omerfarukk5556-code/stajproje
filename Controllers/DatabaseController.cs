using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using StajWebProjesi.Models;
using System.Text.Json;
using Microsoft.AspNetCore.Http;

namespace StajWebProjesi.Controllers;

[Route("[controller]/[action]")]
public class DatabaseController : Controller
{
    // Reusable JSON options to avoid creating new instances on every serialization
    private static readonly JsonSerializerOptions CaseInsensitiveJsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    [HttpGet]
    public IActionResult GetConnectionStatus()
    {
        var connectionInfo = HttpContext.Session.GetString("DbConnectionInfo");
        if (string.IsNullOrEmpty(connectionInfo))
        {
            return Json(new { connected = false });
        }

        try
        {
            var model = JsonSerializer.Deserialize<DbConnectionInfo>(connectionInfo);
            string? dbName = model?.Database;
            if (string.IsNullOrWhiteSpace(dbName))
            {
                var connStr = HttpContext.Session.GetString("DbConnectionString");
                if (!string.IsNullOrEmpty(connStr))
                {
                    var builder = new SqlConnectionStringBuilder(connStr);
                    dbName = builder.InitialCatalog ?? "Bilinmeyen";
                }
            }
            return Json(new { connected = true, database = dbName ?? "Bilinmeyen" });
        }
        catch
        {
            return Json(new { connected = false });
        }
    }

    [HttpGet]
    public IActionResult Connect()
    {
        return RedirectToAction("Index", "Home");
    }

    [HttpPost]
    public async Task<IActionResult> Connect(DbConnectionInfo model)
    {
        if (!ModelState.IsValid)
        {
            return Json(new { success = false, error = "Geçersiz bağlantı bilgisi." });
        }

        var tables = new List<string>();
        string? connStr = null;
        try
        {
            connStr = BuildConnectionString(model);
            
            // Validate connection string to prevent injection
            ValidateConnectionString(connStr);

            using var conn = new SqlConnection(connStr);
            await conn.OpenAsync();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT TABLE_SCHEMA + '.' + TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE' ORDER BY TABLE_NAME;";
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                tables.Add(reader.GetString(0));
            }
        }
        catch (Exception ex)
        {
            return Json(new { success = false, error = ex.Message });
        }

        // store connection info in session for later queries
        try
        {
            // Model'i serialize et
            var json = JsonSerializer.Serialize(model);
            HttpContext.Session.SetString("DbConnectionInfo", json);
            
            // AYRICA gerçek connection string'i de kaydet (DataController.GetConnectionString kullanır)
            if (!string.IsNullOrEmpty(connStr))
                HttpContext.Session.SetString("DbConnectionString", connStr);
        }
        catch (Exception ex)
        {
            // Serialization/session write failure - log and continue
            System.Diagnostics.Debug.WriteLine($"Session write failed: {ex.Message}");
        }

        // Veritabanı adını connection string'den çıkar
        string? dbName = GetDatabaseName(model, connStr);

        return Json(new { success = true, tables = tables, database = dbName });
    }

    [HttpPost]
    public IActionResult Disconnect()
    {
        HttpContext.Session.Remove("DbConnectionInfo");
        HttpContext.Session.Remove("DbConnectionString");
        HttpContext.Session.Remove("SelectedTables");
        HttpContext.Session.Remove("ColumnMappings");
        return Json(new { success = true });
    }

    [HttpPost]
    public IActionResult ManageTables([FromForm] string[]? selectedTables)
    {
        if (!ModelState.IsValid)
        {
            return Json(new { success = false, error = "Geçersiz veri." });
        }

        TempData["DbMessage"] = "Seçili tablolar kaydedildi.";
        TempData["SelectedTables"] = string.Join(',', selectedTables ?? Array.Empty<string>());
        
        try
        {
            var json = JsonSerializer.Serialize(selectedTables ?? Array.Empty<string>());
            HttpContext.Session.SetString("SelectedTables", json);
        }
        catch (Exception ex)
        {
            // Serialization failure - session write error
            System.Diagnostics.Debug.WriteLine($"Session write failed: {ex.Message}");
        }

        return RedirectToAction("Connect");
    }

    [HttpPost]
    public IActionResult ManageTablesAjax([FromBody] string[]? selectedTables)
    {
        if (!ModelState.IsValid)
        {
            return Json(new { success = false, error = "Geçersiz veri." });
        }

        TempData["DbMessage"] = "Seçili tablolar kaydedildi.";
        TempData["SelectedTables"] = string.Join(',', selectedTables ?? Array.Empty<string>());
        
        try
        {
            var json = JsonSerializer.Serialize(selectedTables ?? Array.Empty<string>());
            HttpContext.Session.SetString("SelectedTables", json);
        }
        catch (Exception ex)
        {
            // Serialization failure - session write error
            System.Diagnostics.Debug.WriteLine($"Session write failed: {ex.Message}");
        }

        return Json(new { success = true });
    }

    // ColumnMappingDto Models namespace'inden geliyor (Models/ColumnMappingDto.cs)

    [HttpPost]
    public IActionResult ManageColumnMappingAjax([FromBody] ColumnMappingDto mapping)
    {
        if (!ModelState.IsValid || mapping == null || string.IsNullOrEmpty(mapping.Table))
            return BadRequest(new { success = false, error = "Invalid mapping" });

        try
        {
            // read existing mappings using cached JSON options
            var existingJson = HttpContext.Session.GetString("ColumnMappings");
            var dict = string.IsNullOrEmpty(existingJson)
                ? new Dictionary<string, ColumnMappingDto>(StringComparer.OrdinalIgnoreCase)
                : JsonSerializer.Deserialize<Dictionary<string, ColumnMappingDto>>(existingJson, CaseInsensitiveJsonOptions) 
                  ?? new Dictionary<string, ColumnMappingDto>(StringComparer.OrdinalIgnoreCase);

            dict[mapping.Table] = mapping;
            HttpContext.Session.SetString("ColumnMappings", JsonSerializer.Serialize(dict));
            return Json(new { success = true });
        }
        catch (Exception ex)
        {
            return Json(new { success = false, error = ex.Message });
        }
    }

    // --- Private helpers ---

    private static string BuildConnectionString(DbConnectionInfo model)
    {
        if (!string.IsNullOrWhiteSpace(model.ConnectionString))
        {
            return model.ConnectionString ?? string.Empty;
        }

        var builder = new SqlConnectionStringBuilder();
        builder.DataSource = string.IsNullOrWhiteSpace(model.Server) ? "(localdb)\\MSSQLLocalDB" : model.Server;
        builder.InitialCatalog = string.IsNullOrWhiteSpace(model.Database) ? "proje619" : model.Database;
        
        if (model.Authentication == "Windows")
        {
            builder.IntegratedSecurity = true;
        }
        else
        {
            builder.IntegratedSecurity = false;
            builder.UserID = model.Username ?? string.Empty;
            builder.Password = model.Password ?? string.Empty;
        }
        
        return builder.ConnectionString;
    }

    private static void ValidateConnectionString(string connStr)
    {
        // Connection string injection prevention:
        // Validate using SqlConnectionStringBuilder which sanitizes the input
        try
        {
            _ = new SqlConnectionStringBuilder(connStr);
        }
        catch (ArgumentException ex)
        {
            throw new InvalidOperationException($"Geçersiz bağlantı dizesi: {ex.Message}");
        }
    }

    private static string? GetDatabaseName(DbConnectionInfo model, string? connStr)
    {
        string? dbName = model.Database;
        if (string.IsNullOrWhiteSpace(dbName) && !string.IsNullOrEmpty(connStr))
        {
            var builder = new SqlConnectionStringBuilder(connStr);
            dbName = builder.InitialCatalog ?? "Bilinmeyen";
        }
        return dbName ?? "Bilinmeyen";
    }
}
