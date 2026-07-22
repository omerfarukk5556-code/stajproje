�
PC:\Users\omer\Desktop\staj proje\StajWebProjesi\Controllers\AccountController.cs�using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.Sqlite;
using System.Security.Cryptography;
using System.Text;
using IO = System.IO;

namespace StajWebProjesi.Controllers
{
    [AllowAnonymous]
    public class AccountController : Controller
    {
        private static string GetConnectionString()
        {
            // Proje kök dizinini bul - AppContext.BaseDirectory'den parent'a çıkarak
            string baseDir = AppContext.BaseDirectory;
            // Geliştirme ortamında bin/Debug/netX.0/ altında olabilir, proje köküne çıkalım
            var dir = new IO.DirectoryInfo(baseDir);
            while (dir.Parent != null && !IO.File.Exists(Path.Combine(dir.FullName, "stajweb.db")))
            {
                dir = dir.Parent;
            }
            string dbPath = Path.Combine(dir.FullName, "stajweb.db");
            return $"Data Source={dbPath}";
        }

        private static string HashPassword(string password)
        {
            var hashedBytes = SHA256.HashData(Encoding.UTF8.GetBytes(password));
            return Convert.ToHexStringLower(hashedBytes);
        }
        
        [HttpGet]
        public IActionResult Login() => View();

        [HttpPost]
        public IActionResult Login(string Username, string Password, string actionType) 
        {
            var connString = GetConnectionString();
            using var conn = new SqliteConnection(connString);
            conn.Open();

            string hashedPassword = HashPassword(Password);

            if (actionType == "register")
            {
                var createTableCmd = new SqliteCommand(@"CREATE TABLE IF NOT EXISTS Users (
                                                    Id INTEGER PRIMARY KEY AUTOINCREMENT, 
                                                    Username TEXT NOT NULL, 
                                                    Password TEXT NOT NULL)", conn);
                createTableCmd.ExecuteNonQuery();

                var insertCmd = new SqliteCommand("INSERT INTO Users (Username, Password) VALUES (@u, @p)", conn);
                insertCmd.Parameters.AddWithValue("@u", Username);
                insertCmd.Parameters.AddWithValue("@p", hashedPassword);
                insertCmd.ExecuteNonQuery();

                TempData["Success"] = "Kayıt başarılı, şimdi giriş yapabilirsin!";
                return RedirectToAction(nameof(Login));
            }

            var cmd = new SqliteCommand("SELECT Id, Username FROM Users WHERE Username=@u AND Password=@p", conn);
            cmd.Parameters.AddWithValue("@u", Username);
            cmd.Parameters.AddWithValue("@p", hashedPassword);
            
            using var reader = cmd.ExecuteReader();
            if (reader.Read())
            {
                HttpContext.Session.SetString("UserId", reader["Id"]?.ToString() ?? "");
                HttpContext.Session.SetString("Username", reader["Username"]?.ToString() ?? "");
                return RedirectToAction("Index", "Home");
            }

            TempData["Error"] = "Hatalı giriş!";
            return RedirectToAction(nameof(Login));
        }

        [HttpPost]
        public IActionResult Logout()
        {
            HttpContext.Session.Clear();
            return Json(new { success = true });
        }
    }
}
ParseOptions.0.json�D
QC:\Users\omer\Desktop\staj proje\StajWebProjesi\Controllers\DatabaseController.cs�Cusing Microsoft.AspNetCore.Mvc;
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
ParseOptions.0.json׶
MC:\Users\omer\Desktop\staj proje\StajWebProjesi\Controllers\DataController.cs�using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using StajWebProjesi.Models;

namespace StajWebProjesi.Controllers;

using Microsoft.AspNetCore.Mvc; 
using Microsoft.AspNetCore.Authorization;

//[Authorize] // Bunu ekle
[ApiController]
[Route("[controller]")]
public class DataController : ControllerBase

{
    // Constants
    private const string SessionKeyDbConnectionInfo = "DbConnectionInfo";
    private const string SessionKeyDbConnectionString = "DbConnectionString";
    private const string TimestampColumnName = "Timestamp";

    // Reusable JSON options
    private static readonly JsonSerializerOptions CaseInsensitiveJsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    private string? GetConnectionString()
    {
        // Önce doğrudan kaydedilen connection string'i dene
        var connStr = HttpContext.Session.GetString(SessionKeyDbConnectionString);
        if (!string.IsNullOrEmpty(connStr))
        {
            return connStr;
        }
        
        // Fallback: JSON'dan deserialize et
        var conn = HttpContext.Session.GetString(SessionKeyDbConnectionInfo);
        if (string.IsNullOrEmpty(conn))
        {
            throw new InvalidOperationException("LÜTFEN ÖNCE BAĞLANTI MODALINI KULLANIN.");
        }
        
        // JSON'dan DbConnectionInfo nesnesini deserialize et ve bağlantı dizesini oluştur
        var info = JsonSerializer.Deserialize<DbConnectionInfo>(conn);
        if (info == null) throw new InvalidOperationException("Geçersiz bağlantı bilgisi.");
        
        var builder = new SqlConnectionStringBuilder();
        builder.DataSource = string.IsNullOrWhiteSpace(info.Server) ? "(localdb)\\MSSQLLocalDB" : info.Server;
        builder.InitialCatalog = string.IsNullOrWhiteSpace(info.Database) ? "proje619" : info.Database;
        if (info.Authentication == "Windows")
        {
            builder.IntegratedSecurity = true;
        }
        else
        {
            builder.IntegratedSecurity = false;
            builder.UserID = info.Username ?? string.Empty;
            builder.Password = info.Password ?? string.Empty;
        }
        return builder.ConnectionString;
    }

    [HttpGet("GetBatches")]
    public async Task<IActionResult> GetBatches([FromQuery] int batchId = 0)
    {
        try
        {
            if (string.IsNullOrEmpty(HttpContext.Session.GetString(SessionKeyDbConnectionString)) &&
                string.IsNullOrEmpty(HttpContext.Session.GetString(SessionKeyDbConnectionInfo)))
            {
                return BadRequest(new { error = "Önce veritabanına bağlanın." });
            }
            var connectionString = GetConnectionString() ?? throw new InvalidOperationException("Bağlantı bilgisi bulunamadı.");
            using var conn = new SqlConnection(connectionString);
            await conn.OpenAsync();

            var sql = "SELECT BATCH_ID, SHIP_NAME, BATCH_DATE, LOAD_TYPE FROM BATCH_MASTER ORDER BY BATCH_DATE DESC";
            
            using var cmd = new SqlCommand(sql, conn);
            using var reader = await cmd.ExecuteReaderAsync();
            var batches = new List<object>();

            while (await reader.ReadAsync())
            {
                batches.Add(new
                {
                    batchId = Convert.ToInt32(reader.GetValue(0)),
                    shipName = reader.IsDBNull(1) ? "" : reader.GetString(1),
                    batchDate = reader.IsDBNull(2) ? (DateTime?)null : reader.GetDateTime(2),
                    loadType = reader.IsDBNull(3) ? "" : reader.GetString(3)
                });
            }

            return Ok(new { batches });
        }
        catch (Exception ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    [HttpGet("GetHistTrendByBatch")]
    public async Task<IActionResult> GetHistTrendByBatch([FromQuery] int batchId, [FromQuery] string columns = "FL1,TEMP1,PRES1", [FromQuery] int limit = 0, [FromQuery] string timeRange = "daily", [FromQuery] int yearCount = 1)
    {
        try
        {
            var connectionString = GetConnectionString() ?? throw new InvalidOperationException("Bağlantı bilgisi bulunamadı.");
            using var conn = new SqlConnection(connectionString);
            await conn.OpenAsync();

            // 1. Timestamp kolonunu otomatik bul
            var tsCol = await FindTimestampColumnAsync(conn);
            
            // 2. Batch ID kolonunu bul
            var batchCol = await FindBatchIdColumnAsync(conn);
            
            // 3. Mevcut kolonları keşfet ve geçerli olanları filtrele
            var (requestedCols, validCols, colList, selectCols) = await FilterValidColumnsAsync(conn, columns, tsCol, batchCol);
            
            // 4. Batch'in EN SONU tarihini bul
            var batchEndDate = await GetBatchEndDateAsync(conn, batchCol, batchId, tsCol);
            
            // 5. Zaman aralığı filtresini oluştur
            var timeFilter = BuildTimeFilter(tsCol, batchEndDate, timeRange, yearCount);
            
            // 6. Sorguyu oluştur ve çalıştır
            var sql = $"SELECT [{tsCol}], {selectCols} FROM dbo.HIST_TREND WHERE [{batchCol}] = @batchId{timeFilter} ORDER BY [{tsCol}] ASC";
            
            using var cmd = new SqlCommand(sql, conn);
            cmd.Parameters.AddWithValue("@batchId", batchId);
            if (batchEndDate.HasValue)
                cmd.Parameters.AddWithValue("@batchEnd", batchEndDate.Value);

            // 7. Veriyi çek ve seyrelt
            var result = await ReadAndSampleSeriesAsync(cmd, requestedCols, validCols, colList);
            
            return Ok(new { 
                labels = result.Labels, 
                series = result.Series, 
                meta = new { timeRange, yearCount, totalRecords = result.TotalRecords, batchEnd = batchEndDate?.ToString("yyyy-MM-dd HH:mm:ss") ?? "null" } 
            });
        }
        catch (Exception ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    // --- Refactored helper methods to reduce cognitive complexity ---

    private static async Task<string> FindTimestampColumnAsync(SqlConnection conn)
    {
        var tsCol = TimestampColumnName;
        string findTsSql = @"SELECT TOP 1 COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS 
                             WHERE TABLE_NAME = 'HIST_TREND' 
                             AND DATA_TYPE IN ('datetime','datetime2','date','smalldatetime')
                             ORDER BY ORDINAL_POSITION";
        using (var cmdTs = new SqlCommand(findTsSql, conn))
        {
            var tsResult = await cmdTs.ExecuteScalarAsync();
            if (tsResult != null) tsCol = tsResult.ToString()!;
        }
        return tsCol;
    }

    private static async Task<string> FindBatchIdColumnAsync(SqlConnection conn)
    {
        var batchCol = "BATCH_ID";
        string findBatchSql = @"SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS 
                                WHERE TABLE_NAME = 'HIST_TREND' 
                                AND COLUMN_NAME LIKE '%BATCH%'";
        using (var cmdB = new SqlCommand(findBatchSql, conn))
        {
            var batchResult = await cmdB.ExecuteScalarAsync();
            if (batchResult != null) batchCol = batchResult.ToString()!;
        }
        return batchCol;
    }

    private static async Task<(List<string> Requested, List<string> Valid, List<string> ColList, string SelectCols)> FilterValidColumnsAsync(SqlConnection conn, string columns, string tsCol, string batchCol)
    {
        var requestedCols = columns.Split(',').Select(c => c.Trim()).ToList();
        string findExistingSql = @"SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS 
                                   WHERE TABLE_NAME = 'HIST_TREND'";
        var existingCols = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        using (var cmdEx = new SqlCommand(findExistingSql, conn))
        {
            using var readerEx = await cmdEx.ExecuteReaderAsync();
            while (await readerEx.ReadAsync())
                existingCols.Add(readerEx.GetString(0));
        }

        existingCols.Add(tsCol);
        existingCols.Add(batchCol);

        var validCols = requestedCols.Where(c => existingCols.Contains(c)).ToList();
        var colList = validCols.Select(c => $"[{c}]").ToList();
        var selectCols = string.Join(", ", colList);
        return (requestedCols, validCols, colList, selectCols);
    }

    private static async Task<DateTime?> GetBatchEndDateAsync(SqlConnection conn, string batchCol, int batchId, string tsCol)
    {
        DateTime? batchEndDate = null;
        string batchDateSql = $"SELECT MAX([{tsCol}]) FROM dbo.HIST_TREND WHERE [{batchCol}] = @batchId";
        using (var cmdBatch = new SqlCommand(batchDateSql, conn))
        {
            cmdBatch.Parameters.AddWithValue("@batchId", batchId);
            var tsResult = await cmdBatch.ExecuteScalarAsync();
            if (tsResult != null && tsResult != DBNull.Value)
                batchEndDate = (DateTime)tsResult;
        }
        return batchEndDate;
    }

    private static string BuildTimeFilter(string tsCol, DateTime? batchEndDate, string timeRange, int yearCount)
    {
        if (!batchEndDate.HasValue) return "";
        
        string datePart = timeRange switch
        {
            "daily" => "day",
            "monthly" => "month",
            "yearly" => "year",
            _ => "day"
        };
        
        return $" AND [{tsCol}] >= DATEADD({datePart}, -{yearCount}, @batchEnd) AND [{tsCol}] <= @batchEnd";
    }

    private record SeriesResult(List<string> Labels, Dictionary<string, List<double>> Series, int TotalRecords);

    private static async Task<SeriesResult> ReadAndSampleSeriesAsync(SqlCommand cmd, List<string> requestedCols, List<string> validCols, List<string> colList)
    {
        using var reader = await cmd.ExecuteReaderAsync();
        
        var allLabels = new List<string>();
        var allSeries = new Dictionary<string, List<double>>();
        foreach (var col in requestedCols)
            allSeries[col] = new List<double>();
        
        while (await reader.ReadAsync())
        {
            var dt = reader.GetDateTime(0);
            string label = dt.ToString("dd.MM.yyyy HH:mm");
            allLabels.Add(label);
            for (int i = 0; i < colList.Count; i++)
            {
                var colName = validCols[i];
                var val = reader.IsDBNull(i + 1) ? double.NaN : Convert.ToDouble(reader.GetValue(i + 1));
                allSeries[colName].Add(val);
            }
        }

        // Sampling
        const int maxPoints = 500;
        List<string> labels;
        Dictionary<string, List<double>> seriesData;

        if (allLabels.Count > maxPoints)
        {
            labels = new List<string>(maxPoints);
            seriesData = requestedCols.ToDictionary(c => c, _ => new List<double>(maxPoints));
            double step = (double)allLabels.Count / maxPoints;
            for (int i = 0; i < maxPoints; i++)
            {
                int idx = Math.Min((int)(i * step), allLabels.Count - 1);
                labels.Add(allLabels[idx]);
                foreach (var col in validCols)
                    seriesData[col].Add(allSeries[col][idx]);
            }
        }
        else
        {
            labels = allLabels;
            seriesData = allSeries;
        }

        return new SeriesResult(labels, seriesData, allLabels.Count);
    }

    [HttpGet("GetBatchComparison")]
    public async Task<IActionResult> GetBatchComparison([FromQuery] int batchId)
    {
        try
        {
            var connectionString = GetConnectionString() ?? throw new InvalidOperationException("Bağlantı bilgisi bulunamadı.");

            // 1. BATCH_MASTER konsimento kolonlarını keşfet
            var bmCols = await GetBmKonsimentoColumnsAsync(connectionString);
            
            // 2. HIST_TREND kolonlarını keşfet
            var htCols = await GetHtColumnsAsync(connectionString);
            
            // 3. Batch ID kolonunu keşfet
            var batchCol = await GetBatchColFromHtAsync(connectionString);

            // 4. Kolon isimlerini belirle
            string konsVolCol = bmCols.FirstOrDefault(c => c.Contains("VOLUME")) ?? bmCols.FirstOrDefault(c => c.Contains("GSV")) ?? "KONSIMENTO_VOLUME";
            string konsMassCol = bmCols.FirstOrDefault(c => c.Contains("MASS") || c.Contains("WEIGHT")) ?? "KONSIMENTO_MASS";
            string gsColName = htCols.FirstOrDefault(c => c == "GS") ?? htCols.FirstOrDefault() ?? "GS";
            string massColName = htCols.Count > 1 ? htCols.LastOrDefault(c => c == "MASS") ?? htCols[^1] : htCols.FirstOrDefault(c => c != gsColName) ?? "MASS";

            // 5. Tek sorgu ile tüm değerleri al
            using (var conn4 = new SqlConnection(connectionString))
            {
                await conn4.OpenAsync();
                string sqlAll = $@"
                    SELECT 
                        bm.{konsVolCol} AS KonsimentoGSV,
                        bm.{konsMassCol} AS KonsimentoMass,
                        (SELECT MAX([{gsColName}]) - MIN([{gsColName}]) FROM HIST_TREND WHERE [{batchCol}] = @batchId) AS SayaçGSV,
                        (SELECT MAX([{massColName}]) - MIN([{massColName}]) FROM HIST_TREND WHERE [{batchCol}] = @batchId) AS SayaçMass
                    FROM BATCH_MASTER bm
                    WHERE bm.BATCH_ID = @batchId";

                using var cmd = new SqlCommand(sqlAll, conn4);
                cmd.Parameters.AddWithValue("@batchId", batchId);
                using var reader = await cmd.ExecuteReaderAsync();
                
                if (await reader.ReadAsync())
                {
                    string gsvKons = reader.IsDBNull(0) ? "0" : reader.GetValue(0)?.ToString() ?? "0";
                    string massKons = reader.IsDBNull(1) ? "0" : reader.GetValue(1)?.ToString() ?? "0";
                    string gsvMeter = reader.IsDBNull(2) ? "0" : reader.GetValue(2)?.ToString() ?? "0";
                    string massMeter = reader.IsDBNull(3) ? "0" : reader.GetValue(3)?.ToString() ?? "0";

                    return Ok(new {
                        gsvKonsement = gsvKons,
                        massKonsement = massKons,
                        gsvMeter = gsvMeter,
                        massMeter = massMeter
                    });
                }
            }

            return Ok(new { gsvKonsement = "0", massKonsement = "0", gsvMeter = "0", massMeter = "0" });
        }
        catch (Exception ex)
        {
            return Ok(new {
                gsvKonsement = 0, massKonsement = 0,
                gsvMeter = 0, massMeter = 0,
                error = ex.Message
            });
        }
    }

    // --- Helper methods for GetBatchComparison to reduce complexity ---

    private static async Task<List<string>> GetBmKonsimentoColumnsAsync(string connectionString)
    {
        using var conn = new SqlConnection(connectionString);
        await conn.OpenAsync();
        var cmd = new SqlCommand("SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'BATCH_MASTER' AND (COLUMN_NAME LIKE '%KONSIMENTO%' OR COLUMN_NAME LIKE '%CONSENT%')", conn);
        using var reader = await cmd.ExecuteReaderAsync();
        var cols = new List<string>();
        while (await reader.ReadAsync()) cols.Add(reader.GetString(0));
        return cols;
    }

    private static async Task<List<string>> GetHtColumnsAsync(string connectionString)
    {
        using var conn = new SqlConnection(connectionString);
        await conn.OpenAsync();
        var cmd = new SqlCommand("SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'HIST_TREND'", conn);
        using var reader = await cmd.ExecuteReaderAsync();
        var cols = new List<string>();
        while (await reader.ReadAsync()) cols.Add(reader.GetString(0));
        return cols;
    }

    private static async Task<string> GetBatchColFromHtAsync(string connectionString)
    {
        using var conn = new SqlConnection(connectionString);
        await conn.OpenAsync();
        var cmd = new SqlCommand("SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'HIST_TREND' AND COLUMN_NAME LIKE '%BATCH%'", conn);
        using var reader = await cmd.ExecuteReaderAsync();
        if (await reader.ReadAsync())
            return reader.GetString(0);
        return "BATCH_ID";
    }

    [HttpGet("SelectedTables")]
    public IActionResult SelectedTables()
    {
        try
        {
            var json = HttpContext.Session.GetString("SelectedTables");
            if (string.IsNullOrEmpty(json)) return Ok(new { selected = Array.Empty<string>() });
            var arr = JsonSerializer.Deserialize<string[]>(json) ?? Array.Empty<string>();
            return Ok(new { selected = arr });
        }
        catch { return Ok(new { selected = Array.Empty<string>() }); }
    }
    
    [HttpPost("Connect")]
    public IActionResult Connect([FromBody] DbConnectionInfo info)
    {
        if (string.IsNullOrEmpty(info.ConnectionString)) 
        {
            info.ConnectionString = $"Server={info.Server};Database={info.Database};Trusted_Connection=True;TrustServerCertificate=True;";
        }
        
        HttpContext.Session.SetString(SessionKeyDbConnectionInfo, JsonSerializer.Serialize(info));
        return Ok();
    }

    [HttpGet("TableColumns")]
    public async Task<IActionResult> TableColumns(string table)
    {
        var connJson = HttpContext.Session.GetString(SessionKeyDbConnectionInfo);
        if (string.IsNullOrEmpty(connJson)) return BadRequest(new { error = "No DB connection in session" });
        
        var info = JsonSerializer.Deserialize<DbConnectionInfo>(connJson);

        var cols = await GetColumnsForTableAsync(table, info!);
        if (cols == null) return BadRequest(new { error = "Could not read table columns" });

        var autoMapping = new ColumnMappingDto
        {
            TimestampColumn = cols.FirstOrDefault(c => c.Contains("DATE", StringComparison.OrdinalIgnoreCase) || c.Contains("TIME", StringComparison.OrdinalIgnoreCase)) ?? TimestampColumnName,
            SelectedColumns = cols.Where(c => 
                c.StartsWith("FL", StringComparison.OrdinalIgnoreCase) || 
                c.StartsWith("TEMP", StringComparison.OrdinalIgnoreCase) || 
                c.StartsWith("PRES", StringComparison.OrdinalIgnoreCase) || 
                c.Equals("DENSITY", StringComparison.OrdinalIgnoreCase)
            ).ToArray()
        };

        return Ok(new { columns = cols, mapping = autoMapping });
    }

    private static async Task<List<string>?> GetColumnsForTableAsync(string table, DbConnectionInfo info)
    {
        if (string.IsNullOrEmpty(table)) return null;
        
        string tableName = table.Contains('.') ? table.Split('.')[^1] : table;
        
        using var conn = new SqlConnection(info.ConnectionString);
        await conn.OpenAsync();
        
        string sql = @"SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = @tableName";
                
        using var cmd = new SqlCommand(sql, conn);
        cmd.Parameters.AddWithValue("@tableName", tableName);
                
        using var reader = await cmd.ExecuteReaderAsync();
        var list = new List<string>();
        while (await reader.ReadAsync()) 
        {
            list.Add(reader.GetString(0));
        }
        
        return list.Count > 0 ? list : null; 
    }

    public class SeriesRequest
    {
        public string? Table { get; set; }
        public string TimestampColumn { get; set; } = TimestampColumnName;
        public string[] Columns { get; set; } = Array.Empty<string>();
        public int Limit { get; set; } = 1200;
        public DateTime? From { get; set; }
        public DateTime? To { get; set; }
    }

    [HttpPost("GetSeries")]
    public async Task<IActionResult> GetSeries([FromBody] SeriesRequest req)
    {
        // Manuel Session Kontrolü
        if (string.IsNullOrEmpty(HttpContext.Session.GetString("UserId"))) 
        {
            return Unauthorized(new { error = "Oturum süresi dolmuş veya giriş yapılmamış." });
        }
        var connJson = HttpContext.Session.GetString(SessionKeyDbConnectionInfo);
        if (string.IsNullOrEmpty(connJson)) return BadRequest(new { error = "Session'da bağlantı bilgisi bulunamadı." });
        
        var info = JsonSerializer.Deserialize<DbConnectionInfo>(connJson);

        if (info == null || string.IsNullOrWhiteSpace(info.ConnectionString))
        {
            return BadRequest(new { error = "ConnectionString null geldi! Bağlantı modalından verileri kaydettiğinden emin ol." });
        }

        string connStr = info.ConnectionString;
        var table = req.Table ?? HttpContext.Session.GetString("SelectedTables")?.Trim('[', ']', '"') ?? "HIST_TREND";
        var tsCol = req.TimestampColumn ?? TimestampColumnName;

        try
        {
            using var conn = new SqlConnection(connStr);
            await conn.OpenAsync();

            // Parametrize table name validation - ensure no SQL injection
            if (!IsValidTableName(table))
            {
                return BadRequest(new { error = "Geçersiz tablo adı." });
            }

            var colsEscaped = req.Columns.Select(c => "[" + EscapeSqlIdentifier(c) + "]").ToArray();
            var sql = $"SELECT TOP (@limit) [{tsCol}], {string.Join(", ", colsEscaped)} FROM {table} ORDER BY [{tsCol}] ASC";
            
            using var cmd = new SqlCommand(sql, conn);
            cmd.Parameters.AddWithValue("@limit", req.Limit);

            using var reader = await cmd.ExecuteReaderAsync();
            var labels = new List<string>();
            var seriesData = req.Columns.ToDictionary(c => c, c => new List<double>());

            while (await reader.ReadAsync())
            {
                labels.Add(reader[0]?.ToString() ?? "");
                foreach (var col in req.Columns)
                {
                    string cleanCol = col.Replace("[", "").Replace("]", "");
                    int ordinal = reader.GetOrdinal(cleanCol);
                    seriesData[col].Add(reader.IsDBNull(ordinal) ? double.NaN : Convert.ToDouble(reader.GetValue(ordinal)));
                }
            }
            return Ok(new { labels, series = seriesData });
        }
        catch (Exception ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    // --- Security helpers ---

    private static bool IsValidTableName(string tableName)
    {
        // Tablo adı sadece harf, rakam, alt çizgi ve noktadan oluşmalıdır
        return System.Text.RegularExpressions.Regex.IsMatch(tableName, @"^[a-zA-Z0-9_\.\[\]]+$");
    }

    private static string EscapeSqlIdentifier(string name)
    {
        // SQL enjeksiyonunu önlemek için köşeli parantez içindeki karakterleri temizle
        return name.Replace("]", "]]");
    }
}
ParseOptions.0.json�
MC:\Users\omer\Desktop\staj proje\StajWebProjesi\Controllers\HomeController.cs�using System.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using StajWebProjesi.Models;

namespace StajWebProjesi.Controllers;

public class HomeController : Controller
{
    [ResponseCache(Duration = 0, Location = ResponseCacheLocation.None, NoStore = true)]
    
    public IActionResult Index()
    {
        // 1. Session kontrolünü en başa al
        if (HttpContext.Session.GetString("UserId") == null)
        {
            return RedirectToAction("Login", "Account");
        }

        // 2. Modelini oluştur
        var model = new BatchSelectionViewModel 
        { 
            HistTrends = new List<HistTrendItem>(),
            Message = "Sistem hazır."
        };
        
        // 3. MODELİ VIEW'A GÖNDER!
        return View(model); 
    }
}
ParseOptions.0.json�

ZC:\Users\omer\Desktop\staj proje\StajWebProjesi\Migrations\20260716054414_InitialCreate.cs�	using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace StajWebProjesi.Migrations
{
    /// <inheritdoc />
    public partial class InitialCreate : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "Users",
                columns: table => new
                {
                    Id = table.Column<int>(type: "INTEGER", nullable: false)
                        .Annotation("Sqlserver:Autoincrement", true),
                    Username = table.Column<string>(type: "TEXT", nullable: false),
                    Email = table.Column<string>(type: "TEXT", nullable: false),
                    Password = table.Column<string>(type: "TEXT", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Users", x => x.Id);
                });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "Users");
        }
    }
}
ParseOptions.0.json�
cC:\Users\omer\Desktop\staj proje\StajWebProjesi\Migrations\20260716054414_InitialCreate.Designer.cs�// <auto-generated />
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Metadata;
using Microsoft.EntityFrameworkCore.Migrations;
using Microsoft.EntityFrameworkCore.Storage.ValueConversion;
using StajWebProjesi.Models;

#nullable disable

namespace StajWebProjesi.Migrations
{
    [DbContext(typeof(AppDbContext))]
    [Migration("20260716054414_InitialCreate")]
    partial class InitialCreate
    {
        /// <inheritdoc />
        protected override void BuildTargetModel(ModelBuilder modelBuilder)
        {
#pragma warning disable 612, 618
            modelBuilder
                .HasAnnotation("ProductVersion", "10.0.9")
                .HasAnnotation("Relational:MaxIdentifierLength", 128);

            SqlServerModelBuilderExtensions.UseIdentityColumns(modelBuilder);

            modelBuilder.Entity("StajWebProjesi.Models.User", b =>
                {
                    b.Property<int>("Id")
                        .ValueGeneratedOnAdd()
                        .HasColumnType("int");

                    SqlServerPropertyBuilderExtensions.UseIdentityColumn(b.Property<int>("Id"));

                    b.Property<string>("Email")
                        .IsRequired()
                        .HasColumnType("nvarchar(max)");

                    b.Property<string>("Password")
                        .IsRequired()
                        .HasColumnType("nvarchar(max)");

                    b.Property<string>("Username")
                        .IsRequired()
                        .HasColumnType("nvarchar(max)");

                    b.HasKey("Id");

                    b.ToTable("Users");
                });
#pragma warning restore 612, 618
        }
    }
}
ParseOptions.0.jsonw
`C:\Users\omer\Desktop\staj proje\StajWebProjesi\Migrations\20260716064835_SqliteInitialCreate.csParseOptions.0.json�
iC:\Users\omer\Desktop\staj proje\StajWebProjesi\Migrations\20260716064835_SqliteInitialCreate.Designer.csParseOptions.0.json�
WC:\Users\omer\Desktop\staj proje\StajWebProjesi\Migrations\AppDbContextModelSnapshot.cs�
// <auto-generated />
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Storage.ValueConversion;
using StajWebProjesi.Models;

#nullable disable

namespace StajWebProjesi.Migrations
{
    [DbContext(typeof(AppDbContext))]
    partial class AppDbContextModelSnapshot : ModelSnapshot
    {
        protected override void BuildModel(ModelBuilder modelBuilder)
        {
#pragma warning disable 612, 618
            modelBuilder.HasAnnotation("ProductVersion", "10.0.10");

            modelBuilder.Entity("StajWebProjesi.Models.User", b =>
                {
                    b.Property<int>("Id")
                        .ValueGeneratedOnAdd()
                        .HasColumnType("INTEGER");

                    b.Property<string>("Email")
                        .IsRequired()
                        .HasColumnType("TEXT");

                    b.Property<string>("Password")
                        .IsRequired()
                        .HasColumnType("TEXT");

                    b.Property<string>("Username")
                        .IsRequired()
                        .HasColumnType("TEXT");

                    b.HasKey("Id");

                    b.ToTable("Users");
                });
#pragma warning restore 612, 618
        }
    }
}
ParseOptions.0.json�
FC:\Users\omer\Desktop\staj proje\StajWebProjesi\Models\AppDbContext.cs�using Microsoft.EntityFrameworkCore;

namespace StajWebProjesi.Models
{
    public class AppDbContext : DbContext
    {
        public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

        public DbSet<User> Users { get; set; }
    }
}ParseOptions.0.json�
MC:\Users\omer\Desktop\staj proje\StajWebProjesi\Models\AppDbContextFactory.cs�using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace StajWebProjesi.Models
{
    public class AppDbContextFactory : IDesignTimeDbContextFactory<AppDbContext>
    {
        public AppDbContext CreateDbContext(string[] args)
        {
            var optionsBuilder = new DbContextOptionsBuilder<AppDbContext>();
            optionsBuilder.UseSqlServer("Server=(localdb)\\MSSQLLocalDB;Database=proje619;Trusted_Connection=True;TrustServerCertificate=True;");
            return new AppDbContext(optionsBuilder.Options);
        }
    }
}ParseOptions.0.json�	
QC:\Users\omer\Desktop\staj proje\StajWebProjesi\Models\BatchSelectionViewModel.cs�namespace StajWebProjesi.Models;

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
ParseOptions.0.json�
JC:\Users\omer\Desktop\staj proje\StajWebProjesi\Models\ColumnMappingDto.cs�namespace StajWebProjesi.Models
{
    public class ColumnMappingDto
    {
        public string? Table { get; set; }
        public string? TimestampColumn { get; set; }
        public string[]? SelectedColumns { get; set; }
    }
}
ParseOptions.0.json�
JC:\Users\omer\Desktop\staj proje\StajWebProjesi\Models\DbConnectionInfo.cs�using System.ComponentModel.DataAnnotations;

namespace StajWebProjesi.Models;

public class DbConnectionInfo
{
    public string? Provider { get; set; }

    [MaxLength(200, ErrorMessage = "Sunucu adı çok uzun.")]
    public string? Server { get; set; }

    [MaxLength(200, ErrorMessage = "Veritabanı adı çok uzun.")]
    public string? Database { get; set; }

    // "Windows" or "SqlServer"
    public string Authentication { get; set; } = "Windows";

    [MaxLength(200, ErrorMessage = "Kullanıcı adı çok uzun.")]
    public string? Username { get; set; }

    [MaxLength(200, ErrorMessage = "Şifre çok uzun.")]
    public string? Password { get; set; }

    [MaxLength(2000, ErrorMessage = "Bağlantı dizesi çok uzun.")]
    public string? ConnectionString { get; set; }
}
ParseOptions.0.json�
HC:\Users\omer\Desktop\staj proje\StajWebProjesi\Models\ErrorViewModel.cs�namespace StajWebProjesi.Models;

public class ErrorViewModel
{
    public string? RequestId { get; set; }

    public bool ShowRequestId => !string.IsNullOrEmpty(RequestId);
}
ParseOptions.0.json�
>C:\Users\omer\Desktop\staj proje\StajWebProjesi\Models\User.cs�namespace StajWebProjesi.Models
{
    public class User
    {
        public int Id { get; set; }
        public string Username { get; set; } = string.Empty;
        public string Email { get; set; } = string.Empty;
        public string Password { get; set; } = string.Empty;
    }
}ParseOptions.0.json�
:C:\Users\omer\Desktop\staj proje\StajWebProjesi\Program.cs�using StajWebProjesi.Models;
using NeoSmart.Caching.Sqlite;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddAuthentication("Cookies")
    .AddCookie("Cookies", options =>
    {
        options.LoginPath = "/Account/Login";
        options.AccessDeniedPath = "/Account/AccessDenied";
    });
// Sadece temel servisleri ekliyoruz, veritabanı kurulumunu kaldırıyoruz
builder.Services.AddControllersWithViews();
// SQLite tabanlı kalıcı distributed cache (F5'te session kaybolmaz)
builder.Services.AddSqliteCache(options =>
{
    options.CachePath = Path.Combine(builder.Environment.ContentRootPath, "session_cache.db");
});
builder.Services.AddSession(options =>
{
    options.IdleTimeout = TimeSpan.FromMinutes(30);
    options.Cookie.HttpOnly = true;
    options.Cookie.IsEssential = true;
});
// Giriş yapılmamışsa kullanıcıyı buraya yönlendir
builder.Services.ConfigureApplicationCookie(options =>
{
    options.LoginPath = "/Account/Login"; // Views klasörünü yazmana gerek yok, controller yolunu yaz
    options.AccessDeniedPath = "/Account/AccessDenied";
});

var app = builder.Build();

app.UseAuthentication(); // Bu mutlaka olmalı




// Hata ayıklama ve statik dosyalar
if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Home/Error");
    app.UseHsts();
}

app.UseHttpsRedirection();
app.UseStaticFiles(); 
app.UseRouting();

app.UseSession(); // Session'ı aktif et
app.UseAuthorization();

// Rota ayarları
app.MapControllers();
app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Account}/{action=Login}/{id?}");

await app.RunAsync();
ParseOptions.0.json�
bC:\Users\omer\Desktop\staj proje\StajWebProjesi\obj\Debug\net10.0\StajWebProjesi.GlobalUsings.g.cs�// <auto-generated/>
global using Microsoft.AspNetCore.Builder;
global using Microsoft.AspNetCore.Hosting;
global using Microsoft.AspNetCore.Http;
global using Microsoft.AspNetCore.Routing;
global using Microsoft.Extensions.Configuration;
global using Microsoft.Extensions.DependencyInjection;
global using Microsoft.Extensions.Hosting;
global using Microsoft.Extensions.Logging;
global using System;
global using System.Collections.Generic;
global using System.IO;
global using System.Linq;
global using System.Net.Http;
global using System.Net.Http.Json;
global using System.Threading;
global using System.Threading.Tasks;
ParseOptions.0.json�
qC:\Users\omer\Desktop\staj proje\StajWebProjesi\obj\Debug\net10.0\.NETCoreApp,Version=v10.0.AssemblyAttributes.cs�// <autogenerated />
using System;
using System.Reflection;
[assembly: global::System.Runtime.Versioning.TargetFrameworkAttribute(".NETCoreApp,Version=v10.0", FrameworkDisplayName = ".NET 10.0")]
ParseOptions.0.json�
`C:\Users\omer\Desktop\staj proje\StajWebProjesi\obj\Debug\net10.0\StajWebProjesi.AssemblyInfo.cs�//------------------------------------------------------------------------------
// <auto-generated>
//     This code was generated by a tool.
//
//     Changes to this file may cause incorrect behavior and will be lost if
//     the code is regenerated.
// </auto-generated>
//------------------------------------------------------------------------------

using System;
using System.Reflection;

[assembly: System.Reflection.AssemblyCompanyAttribute("StajWebProjesi")]
[assembly: System.Reflection.AssemblyConfigurationAttribute("Debug")]
[assembly: System.Reflection.AssemblyFileVersionAttribute("1.0.0.0")]
[assembly: System.Reflection.AssemblyInformationalVersionAttribute("1.0.0+2efbb5a723edfe98d8918b208326e910ee48990f")]
[assembly: System.Reflection.AssemblyProductAttribute("StajWebProjesi")]
[assembly: System.Reflection.AssemblyTitleAttribute("StajWebProjesi")]
[assembly: System.Reflection.AssemblyVersionAttribute("1.0.0.0")]

// Generated by the MSBuild WriteCodeFragment class.

ParseOptions.0.json�
eC:\Users\omer\Desktop\staj proje\StajWebProjesi\obj\Debug\net10.0\StajWebProjesi.RazorAssemblyInfo.cs�//------------------------------------------------------------------------------
// <auto-generated>
//     This code was generated by a tool.
//
//     Changes to this file may cause incorrect behavior and will be lost if
//     the code is regenerated.
// </auto-generated>
//------------------------------------------------------------------------------

using System;
using System.Reflection;

[assembly: Microsoft.AspNetCore.Mvc.ApplicationParts.ProvideApplicationPartFactoryAttribute(("Microsoft.AspNetCore.Mvc.ApplicationParts.ConsolidatedAssemblyApplicationPartFact" +
    "ory, Microsoft.AspNetCore.Mvc.Razor"))]

// Generated by the MSBuild WriteCodeFragment class.

ParseOptions.0.json�
�C:\Users\omer\Desktop\staj proje\StajWebProjesi\obj\Debug\net10.0\Microsoft.AspNetCore.App.SourceGenerators\Microsoft.AspNetCore.SourceGenerators.PublicProgramSourceGenerator\PublicTopLevelProgram.Generated.g.cs�// <auto-generated />
/// <summary>
/// Auto-generated public partial Program class for top-level statement apps.
/// </summary>
public partial class Program { }ParseOptions.0.json٦
�C:\Users\omer\Desktop\staj proje\StajWebProjesi\obj\Debug\net10.0\Microsoft.CodeAnalysis.Razor.Compiler\Microsoft.NET.Sdk.Razor.SourceGenerators.RazorSourceGenerator\Views/Account/Login_cshtml.g.cs��#pragma checksum "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\Account\Login.cshtml" "{8829d00f-11b8-4213-878b-770e8597ac16}" "435192df0670a993312a57ef0cee3075b8452224a4e0b7997e4f7f2c8c491a80"
// <auto-generated/>
#pragma warning disable 1591
[assembly: global::Microsoft.AspNetCore.Razor.Hosting.RazorCompiledItemAttribute(typeof(AspNetCoreGeneratedDocument.Views_Account_Login), @"mvc.1.0.view", @"/Views/Account/Login.cshtml")]
namespace AspNetCoreGeneratedDocument
{
    #line default
    using global::System;
    using global::System.Collections.Generic;
    using global::System.Linq;
    using global::System.Threading.Tasks;
    using global::Microsoft.AspNetCore.Mvc;
    using global::Microsoft.AspNetCore.Mvc.Rendering;
    using global::Microsoft.AspNetCore.Mvc.ViewFeatures;
#nullable restore
#line (1,2)-(1,22) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\_ViewImports.cshtml"
using StajWebProjesi

#nullable disable
    ;
#nullable restore
#line (2,2)-(2,29) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\_ViewImports.cshtml"
using StajWebProjesi.Models

#nullable disable
    ;
    #line default
    #line hidden
    [global::Microsoft.AspNetCore.Razor.Hosting.RazorCompiledItemMetadataAttribute("Identifier", "/Views/Account/Login.cshtml")]
    [global::System.Runtime.CompilerServices.CreateNewOnMetadataUpdateAttribute]
    #nullable restore
    internal sealed class Views_Account_Login : global::Microsoft.AspNetCore.Mvc.Razor.RazorPage<dynamic>
    #nullable disable
    {
        private static readonly global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute __tagHelperAttribute_0 = new global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute("rel", new global::Microsoft.AspNetCore.Html.HtmlString("stylesheet"), global::Microsoft.AspNetCore.Razor.TagHelpers.HtmlAttributeValueStyle.DoubleQuotes);
        private static readonly global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute __tagHelperAttribute_1 = new global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute("href", "~/css/login.css", global::Microsoft.AspNetCore.Razor.TagHelpers.HtmlAttributeValueStyle.DoubleQuotes);
        private static readonly global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute __tagHelperAttribute_2 = new global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute("id", new global::Microsoft.AspNetCore.Html.HtmlString("loginForm"), global::Microsoft.AspNetCore.Razor.TagHelpers.HtmlAttributeValueStyle.DoubleQuotes);
        private static readonly global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute __tagHelperAttribute_3 = new global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute("asp-controller", "Account", global::Microsoft.AspNetCore.Razor.TagHelpers.HtmlAttributeValueStyle.DoubleQuotes);
        private static readonly global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute __tagHelperAttribute_4 = new global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute("asp-action", "Login", global::Microsoft.AspNetCore.Razor.TagHelpers.HtmlAttributeValueStyle.DoubleQuotes);
        private static readonly global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute __tagHelperAttribute_5 = new global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute("method", "post", global::Microsoft.AspNetCore.Razor.TagHelpers.HtmlAttributeValueStyle.DoubleQuotes);
        private static readonly global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute __tagHelperAttribute_6 = new global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute("id", new global::Microsoft.AspNetCore.Html.HtmlString("registerForm"), global::Microsoft.AspNetCore.Razor.TagHelpers.HtmlAttributeValueStyle.DoubleQuotes);
        #line hidden
        #pragma warning disable 0649
        private global::Microsoft.AspNetCore.Razor.Runtime.TagHelpers.TagHelperExecutionContext __tagHelperExecutionContext;
        #pragma warning restore 0649
        private global::Microsoft.AspNetCore.Razor.Runtime.TagHelpers.TagHelperRunner __tagHelperRunner = new global::Microsoft.AspNetCore.Razor.Runtime.TagHelpers.TagHelperRunner();
        #pragma warning disable 0169
        private string __tagHelperStringValueBuffer;
        #pragma warning restore 0169
        private global::Microsoft.AspNetCore.Razor.Runtime.TagHelpers.TagHelperScopeManager __backed__tagHelperScopeManager = null;
        private global::Microsoft.AspNetCore.Razor.Runtime.TagHelpers.TagHelperScopeManager __tagHelperScopeManager
        {
            get
            {
                if (__backed__tagHelperScopeManager == null)
                {
                    __backed__tagHelperScopeManager = new global::Microsoft.AspNetCore.Razor.Runtime.TagHelpers.TagHelperScopeManager(StartTagHelperWritingScope, EndTagHelperWritingScope);
                }
                return __backed__tagHelperScopeManager;
            }
        }
        private global::Microsoft.AspNetCore.Mvc.Razor.TagHelpers.HeadTagHelper __Microsoft_AspNetCore_Mvc_Razor_TagHelpers_HeadTagHelper;
        private global::Microsoft.AspNetCore.Mvc.Razor.TagHelpers.UrlResolutionTagHelper __Microsoft_AspNetCore_Mvc_Razor_TagHelpers_UrlResolutionTagHelper;
        private global::Microsoft.AspNetCore.Mvc.TagHelpers.LinkTagHelper __Microsoft_AspNetCore_Mvc_TagHelpers_LinkTagHelper;
        private global::Microsoft.AspNetCore.Mvc.Razor.TagHelpers.BodyTagHelper __Microsoft_AspNetCore_Mvc_Razor_TagHelpers_BodyTagHelper;
        private global::Microsoft.AspNetCore.Mvc.TagHelpers.FormTagHelper __Microsoft_AspNetCore_Mvc_TagHelpers_FormTagHelper;
        private global::Microsoft.AspNetCore.Mvc.TagHelpers.RenderAtEndOfFormTagHelper __Microsoft_AspNetCore_Mvc_TagHelpers_RenderAtEndOfFormTagHelper;
        #pragma warning disable 1998
        public async override global::System.Threading.Tasks.Task ExecuteAsync()
        {
#nullable restore
#line (1,3)-(3,1) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\Account\Login.cshtml"

    Layout = null;

#line default
#line hidden
#nullable disable

            WriteLiteral("<!DOCTYPE html>\n<html lang=\"tr\">\n");
            __tagHelperExecutionContext = __tagHelperScopeManager.Begin("head", global::Microsoft.AspNetCore.Razor.TagHelpers.TagMode.StartTagAndEndTag, "435192df0670a993312a57ef0cee3075b8452224a4e0b7997e4f7f2c8c491a806316", async() => {
                WriteLiteral("\n    <meta charset=\"UTF-8\">\n    <title>Giriş Yap</title>\n    ");
                __tagHelperExecutionContext = __tagHelperScopeManager.Begin("link", global::Microsoft.AspNetCore.Razor.TagHelpers.TagMode.SelfClosing, "435192df0670a993312a57ef0cee3075b8452224a4e0b7997e4f7f2c8c491a806660", async() => {
                }
                );
                __Microsoft_AspNetCore_Mvc_Razor_TagHelpers_UrlResolutionTagHelper = CreateTagHelper<global::Microsoft.AspNetCore.Mvc.Razor.TagHelpers.UrlResolutionTagHelper>();
                __tagHelperExecutionContext.Add(__Microsoft_AspNetCore_Mvc_Razor_TagHelpers_UrlResolutionTagHelper);
                __Microsoft_AspNetCore_Mvc_TagHelpers_LinkTagHelper = CreateTagHelper<global::Microsoft.AspNetCore.Mvc.TagHelpers.LinkTagHelper>();
                __tagHelperExecutionContext.Add(__Microsoft_AspNetCore_Mvc_TagHelpers_LinkTagHelper);
                __tagHelperExecutionContext.AddHtmlAttribute(__tagHelperAttribute_0);
                __Microsoft_AspNetCore_Mvc_TagHelpers_LinkTagHelper.Href = (string)__tagHelperAttribute_1.Value;
                __tagHelperExecutionContext.AddTagHelperAttribute(__tagHelperAttribute_1);
                __Microsoft_AspNetCore_Mvc_TagHelpers_LinkTagHelper.AppendVersion = 
#nullable restore
#line (9,71)-(9,75) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\Account\Login.cshtml"
true

#line default
#line hidden
#nullable disable
                ;
                __tagHelperExecutionContext.AddTagHelperAttribute("asp-append-version", __Microsoft_AspNetCore_Mvc_TagHelpers_LinkTagHelper.AppendVersion, global::Microsoft.AspNetCore.Razor.TagHelpers.HtmlAttributeValueStyle.DoubleQuotes);
                await __tagHelperRunner.RunAsync(__tagHelperExecutionContext);
                if (!__tagHelperExecutionContext.Output.IsContentModified)
                {
                    await __tagHelperExecutionContext.SetOutputContentAsync();
                }
                Write(__tagHelperExecutionContext.Output);
                __tagHelperExecutionContext = __tagHelperScopeManager.End();
                WriteLiteral("\n");
            }
            );
            __Microsoft_AspNetCore_Mvc_Razor_TagHelpers_HeadTagHelper = CreateTagHelper<global::Microsoft.AspNetCore.Mvc.Razor.TagHelpers.HeadTagHelper>();
            __tagHelperExecutionContext.Add(__Microsoft_AspNetCore_Mvc_Razor_TagHelpers_HeadTagHelper);
            await __tagHelperRunner.RunAsync(__tagHelperExecutionContext);
            if (!__tagHelperExecutionContext.Output.IsContentModified)
            {
                await __tagHelperExecutionContext.SetOutputContentAsync();
            }
            Write(__tagHelperExecutionContext.Output);
            __tagHelperExecutionContext = __tagHelperScopeManager.End();
            WriteLiteral("\n");
            __tagHelperExecutionContext = __tagHelperScopeManager.Begin("body", global::Microsoft.AspNetCore.Razor.TagHelpers.TagMode.StartTagAndEndTag, "435192df0670a993312a57ef0cee3075b8452224a4e0b7997e4f7f2c8c491a809452", async() => {
                WriteLiteral("\n    <div id=\"loginSection\" class=\"login-section active\">\n        \n        <div class=\"login-box\" id=\"loginBox\">\n            <h2>Kullanıcı Girişi</h2>\n            ");
                __tagHelperExecutionContext = __tagHelperScopeManager.Begin("form", global::Microsoft.AspNetCore.Razor.TagHelpers.TagMode.StartTagAndEndTag, "435192df0670a993312a57ef0cee3075b8452224a4e0b7997e4f7f2c8c491a809906", async() => {
                    WriteLiteral(@"
                <input type=""hidden"" name=""actionType"" value=""login"" />
                <label for=""loginUsername"">Kullanıcı Adı</label>
                <input type=""text"" id=""loginUsername"" name=""Username"" placeholder=""Kullanıcı Adı"" required aria-label=""Kullanıcı Adı"" />
                <label for=""loginPassword"">Şifre</label>
                <input type=""password"" id=""loginPassword"" name=""Password"" placeholder=""Şifre"" required aria-label=""Şifre"" />
                <button type=""submit"" class=""btn btn-primary"">Giriş Yap</button>
            ");
                }
                );
                __Microsoft_AspNetCore_Mvc_TagHelpers_FormTagHelper = CreateTagHelper<global::Microsoft.AspNetCore.Mvc.TagHelpers.FormTagHelper>();
                __tagHelperExecutionContext.Add(__Microsoft_AspNetCore_Mvc_TagHelpers_FormTagHelper);
                __Microsoft_AspNetCore_Mvc_TagHelpers_RenderAtEndOfFormTagHelper = CreateTagHelper<global::Microsoft.AspNetCore.Mvc.TagHelpers.RenderAtEndOfFormTagHelper>();
                __tagHelperExecutionContext.Add(__Microsoft_AspNetCore_Mvc_TagHelpers_RenderAtEndOfFormTagHelper);
                __tagHelperExecutionContext.AddHtmlAttribute(__tagHelperAttribute_2);
                __Microsoft_AspNetCore_Mvc_TagHelpers_FormTagHelper.Controller = (string)__tagHelperAttribute_3.Value;
                __tagHelperExecutionContext.AddTagHelperAttribute(__tagHelperAttribute_3);
                __Microsoft_AspNetCore_Mvc_TagHelpers_FormTagHelper.Action = (string)__tagHelperAttribute_4.Value;
                __tagHelperExecutionContext.AddTagHelperAttribute(__tagHelperAttribute_4);
                __Microsoft_AspNetCore_Mvc_TagHelpers_FormTagHelper.Method = (string)__tagHelperAttribute_5.Value;
                __tagHelperExecutionContext.AddTagHelperAttribute(__tagHelperAttribute_5);
                await __tagHelperRunner.RunAsync(__tagHelperExecutionContext);
                if (!__tagHelperExecutionContext.Output.IsContentModified)
                {
                    await __tagHelperExecutionContext.SetOutputContentAsync();
                }
                Write(__tagHelperExecutionContext.Output);
                __tagHelperExecutionContext = __tagHelperScopeManager.End();
                WriteLiteral("\n");
#nullable restore
#line (24,14)-(26,1) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\Account\Login.cshtml"
if (TempData["Error"] != null)
            {

#line default
#line hidden
#nullable disable

                WriteLiteral("                <div class=\"message-box error-message\" role=\"alert\" style=\"margin-top: 15px; padding: 10px; border-radius: 8px; background: #ffe8e8; color: #c62828; font-size: 0.95rem; text-align: center;\">");
                Write(
#nullable restore
#line (26,208)-(26,225) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\Account\Login.cshtml"
TempData["Error"]

#line default
#line hidden
#nullable disable
                );
                WriteLiteral("</div>\n");
#nullable restore
#line (27,1)-(28,1) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\Account\Login.cshtml"
            }

#line default
#line hidden
#nullable disable

#nullable restore
#line (28,14)-(30,1) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\Account\Login.cshtml"
if (TempData["Success"] != null)
            {

#line default
#line hidden
#nullable disable

                WriteLiteral("                <div class=\"message-box success-message\" role=\"alert\" style=\"margin-top: 15px; padding: 10px; border-radius: 8px; background: #f1fce2; color: #4caf50; font-size: 0.95rem; text-align: center;\">");
                Write(
#nullable restore
#line (30,210)-(30,229) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\Account\Login.cshtml"
TempData["Success"]

#line default
#line hidden
#nullable disable
                );
                WriteLiteral("</div>\n");
#nullable restore
#line (31,1)-(32,1) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\Account\Login.cshtml"
            }

#line default
#line hidden
#nullable disable

                WriteLiteral(@"            <div style=""margin-top: 20px; text-align: center;"">
                <p style=""color: #666; font-size: 0.9rem;"">Hesabın yok mu? 
                    <button type=""button"" id=""btnShowRegister"" style=""background:none; border:none; color: var(--primary); cursor:pointer; text-decoration:underline;"">Kayıt Ol</button>
                </p>
            </div>
        </div>

        <!-- Kayıt Formu -->
        <div class=""login-box"" id=""registerBox"" style=""display: none;"">
            <h2>Kayıt Ol</h2>
            ");
                __tagHelperExecutionContext = __tagHelperScopeManager.Begin("form", global::Microsoft.AspNetCore.Razor.TagHelpers.TagMode.StartTagAndEndTag, "435192df0670a993312a57ef0cee3075b8452224a4e0b7997e4f7f2c8c491a8014945", async() => {
                    WriteLiteral(@"
                <label for=""regUsername"">Kullanıcı Adı</label>
                <input type=""text"" id=""regUsername"" name=""Username"" placeholder=""Kullanıcı Adı"" required aria-label=""Kullanıcı Adı"" />
                <label for=""regEmail"">E-posta</label>
                <input type=""email"" id=""regEmail"" name=""Email"" placeholder=""E-posta"" required aria-label=""E-posta"" />
                <label for=""regPassword"">Şifre</label>
                <input type=""password"" id=""regPassword"" name=""Password"" placeholder=""Şifre"" required aria-label=""Şifre"" />
                
                <input type=""hidden"" name=""actionType"" value=""register"" />
                
                <button type=""submit"" class=""btn btn-primary"">Kayıt Ol</button>
            ");
                }
                );
                __Microsoft_AspNetCore_Mvc_TagHelpers_FormTagHelper = CreateTagHelper<global::Microsoft.AspNetCore.Mvc.TagHelpers.FormTagHelper>();
                __tagHelperExecutionContext.Add(__Microsoft_AspNetCore_Mvc_TagHelpers_FormTagHelper);
                __Microsoft_AspNetCore_Mvc_TagHelpers_RenderAtEndOfFormTagHelper = CreateTagHelper<global::Microsoft.AspNetCore.Mvc.TagHelpers.RenderAtEndOfFormTagHelper>();
                __tagHelperExecutionContext.Add(__Microsoft_AspNetCore_Mvc_TagHelpers_RenderAtEndOfFormTagHelper);
                __tagHelperExecutionContext.AddHtmlAttribute(__tagHelperAttribute_6);
                __Microsoft_AspNetCore_Mvc_TagHelpers_FormTagHelper.Controller = (string)__tagHelperAttribute_3.Value;
                __tagHelperExecutionContext.AddTagHelperAttribute(__tagHelperAttribute_3);
                __Microsoft_AspNetCore_Mvc_TagHelpers_FormTagHelper.Action = (string)__tagHelperAttribute_4.Value;
                __tagHelperExecutionContext.AddTagHelperAttribute(__tagHelperAttribute_4);
                __Microsoft_AspNetCore_Mvc_TagHelpers_FormTagHelper.Method = (string)__tagHelperAttribute_5.Value;
                __tagHelperExecutionContext.AddTagHelperAttribute(__tagHelperAttribute_5);
                await __tagHelperRunner.RunAsync(__tagHelperExecutionContext);
                if (!__tagHelperExecutionContext.Output.IsContentModified)
                {
                    await __tagHelperExecutionContext.SetOutputContentAsync();
                }
                Write(__tagHelperExecutionContext.Output);
                __tagHelperExecutionContext = __tagHelperScopeManager.End();
                WriteLiteral(@"
            <div style=""margin-top: 20px; text-align: center;"">
                <button type=""button"" id=""btnShowLogin"" style=""background:none; border:none; color: var(--primary); cursor:pointer; text-decoration:underline;"">Giriş Ekranına Dön</button>
            </div>
        </div>

    </div>

    <script>
        function toggleForms() {
            var loginBox = document.getElementById('loginBox');
            var registerBox = document.getElementById('registerBox');
            if (loginBox.style.display === 'none') {
                loginBox.style.display = 'block';
                registerBox.style.display = 'none';
            } else {
                loginBox.style.display = 'none';
                registerBox.style.display = 'block';
            }
        }

        document.addEventListener('DOMContentLoaded', function() {
            var btnShowRegister = document.getElementById('btnShowRegister');
            if (btnShowRegister) {
                btnShowRegister.addEventListener('click', tog");
                WriteLiteral("gleForms);\n            }\n            var btnShowLogin = document.getElementById(\'btnShowLogin\');\n            if (btnShowLogin) {\n                btnShowLogin.addEventListener(\'click\', toggleForms);\n            }\n        });\n    </script>\n");
            }
            );
            __Microsoft_AspNetCore_Mvc_Razor_TagHelpers_BodyTagHelper = CreateTagHelper<global::Microsoft.AspNetCore.Mvc.Razor.TagHelpers.BodyTagHelper>();
            __tagHelperExecutionContext.Add(__Microsoft_AspNetCore_Mvc_Razor_TagHelpers_BodyTagHelper);
            await __tagHelperRunner.RunAsync(__tagHelperExecutionContext);
            if (!__tagHelperExecutionContext.Output.IsContentModified)
            {
                await __tagHelperExecutionContext.SetOutputContentAsync();
            }
            Write(__tagHelperExecutionContext.Output);
            __tagHelperExecutionContext = __tagHelperScopeManager.End();
            WriteLiteral("\n</html>\n");
        }
        #pragma warning restore 1998
        #nullable restore
        [global::Microsoft.AspNetCore.Mvc.Razor.Internal.RazorInjectAttribute]
        public global::Microsoft.AspNetCore.Mvc.ViewFeatures.IModelExpressionProvider ModelExpressionProvider { get; private set; } = default!;
        #nullable disable
        #nullable restore
        [global::Microsoft.AspNetCore.Mvc.Razor.Internal.RazorInjectAttribute]
        public global::Microsoft.AspNetCore.Mvc.IUrlHelper Url { get; private set; } = default!;
        #nullable disable
        #nullable restore
        [global::Microsoft.AspNetCore.Mvc.Razor.Internal.RazorInjectAttribute]
        public global::Microsoft.AspNetCore.Mvc.IViewComponentHelper Component { get; private set; } = default!;
        #nullable disable
        #nullable restore
        [global::Microsoft.AspNetCore.Mvc.Razor.Internal.RazorInjectAttribute]
        public global::Microsoft.AspNetCore.Mvc.Rendering.IJsonHelper Json { get; private set; } = default!;
        #nullable disable
        #nullable restore
        [global::Microsoft.AspNetCore.Mvc.Razor.Internal.RazorInjectAttribute]
        public global::Microsoft.AspNetCore.Mvc.Rendering.IHtmlHelper<dynamic> Html { get; private set; } = default!;
        #nullable disable
    }
}
#pragma warning restore 1591
ParseOptions.0.json�Q
�C:\Users\omer\Desktop\staj proje\StajWebProjesi\obj\Debug\net10.0\Microsoft.CodeAnalysis.Razor.Compiler\Microsoft.NET.Sdk.Razor.SourceGenerators.RazorSourceGenerator\Views/Database/Tables_cshtml.g.cs�O#pragma checksum "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\Database\Tables.cshtml" "{8829d00f-11b8-4213-878b-770e8597ac16}" "a3e33d345e05ff1def5c27a002213b927331b81e4d5ad13880f1c65e28458d87"
// <auto-generated/>
#pragma warning disable 1591
[assembly: global::Microsoft.AspNetCore.Razor.Hosting.RazorCompiledItemAttribute(typeof(AspNetCoreGeneratedDocument.Views_Database_Tables), @"mvc.1.0.view", @"/Views/Database/Tables.cshtml")]
namespace AspNetCoreGeneratedDocument
{
    #line default
    using global::System;
    using global::System.Collections.Generic;
    using global::System.Linq;
    using global::System.Threading.Tasks;
    using global::Microsoft.AspNetCore.Mvc;
    using global::Microsoft.AspNetCore.Mvc.Rendering;
    using global::Microsoft.AspNetCore.Mvc.ViewFeatures;
#nullable restore
#line (1,2)-(1,22) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\_ViewImports.cshtml"
using StajWebProjesi

#nullable disable
    ;
#nullable restore
#line (2,2)-(2,29) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\_ViewImports.cshtml"
using StajWebProjesi.Models

#nullable disable
    ;
    #line default
    #line hidden
    [global::Microsoft.AspNetCore.Razor.Hosting.RazorCompiledItemMetadataAttribute("Identifier", "/Views/Database/Tables.cshtml")]
    [global::System.Runtime.CompilerServices.CreateNewOnMetadataUpdateAttribute]
    #nullable restore
    internal sealed class Views_Database_Tables : global::Microsoft.AspNetCore.Mvc.Razor.RazorPage<
#nullable restore
#line (1,8)-(1,46) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\Database\Tables.cshtml"
StajWebProjesi.Models.DbConnectionInfo

#line default
#line hidden
#nullable disable
    >
    #nullable disable
    {
        private static readonly global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute __tagHelperAttribute_0 = new global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute("asp-action", "ManageTables", global::Microsoft.AspNetCore.Razor.TagHelpers.HtmlAttributeValueStyle.DoubleQuotes);
        private static readonly global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute __tagHelperAttribute_1 = new global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute("method", "post", global::Microsoft.AspNetCore.Razor.TagHelpers.HtmlAttributeValueStyle.DoubleQuotes);
        #line hidden
        #pragma warning disable 0649
        private global::Microsoft.AspNetCore.Razor.Runtime.TagHelpers.TagHelperExecutionContext __tagHelperExecutionContext;
        #pragma warning restore 0649
        private global::Microsoft.AspNetCore.Razor.Runtime.TagHelpers.TagHelperRunner __tagHelperRunner = new global::Microsoft.AspNetCore.Razor.Runtime.TagHelpers.TagHelperRunner();
        #pragma warning disable 0169
        private string __tagHelperStringValueBuffer;
        #pragma warning restore 0169
        private global::Microsoft.AspNetCore.Razor.Runtime.TagHelpers.TagHelperScopeManager __backed__tagHelperScopeManager = null;
        private global::Microsoft.AspNetCore.Razor.Runtime.TagHelpers.TagHelperScopeManager __tagHelperScopeManager
        {
            get
            {
                if (__backed__tagHelperScopeManager == null)
                {
                    __backed__tagHelperScopeManager = new global::Microsoft.AspNetCore.Razor.Runtime.TagHelpers.TagHelperScopeManager(StartTagHelperWritingScope, EndTagHelperWritingScope);
                }
                return __backed__tagHelperScopeManager;
            }
        }
        private global::Microsoft.AspNetCore.Mvc.TagHelpers.FormTagHelper __Microsoft_AspNetCore_Mvc_TagHelpers_FormTagHelper;
        private global::Microsoft.AspNetCore.Mvc.TagHelpers.RenderAtEndOfFormTagHelper __Microsoft_AspNetCore_Mvc_TagHelpers_RenderAtEndOfFormTagHelper;
        #pragma warning disable 1998
        public async override global::System.Threading.Tasks.Task ExecuteAsync()
        {
            WriteLiteral("\r\n");
#nullable restore
#line (3,3)-(7,1) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\Database\Tables.cshtml"

    ViewData["Title"] = "Tablolar";
    var tables = ViewData["Tables"] as List<string> ?? new List<string>();
    var selected = (TempData["SelectedTables"] as string ?? "").Split(',', StringSplitOptions.RemoveEmptyEntries);

#line default
#line hidden
#nullable disable

            WriteLiteral("\r\n<h2>Tablolar</h2>\r\n\r\n");
            __tagHelperExecutionContext = __tagHelperScopeManager.Begin("form", global::Microsoft.AspNetCore.Razor.TagHelpers.TagMode.StartTagAndEndTag, "a3e33d345e05ff1def5c27a002213b927331b81e4d5ad13880f1c65e28458d874561", async() => {
                WriteLiteral("\r\n    <div class=\"mb-3\">\r\n");
#nullable restore
#line (13,10)-(15,1) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\Database\Tables.cshtml"
foreach (var t in tables)
        {

#line default
#line hidden
#nullable disable

                WriteLiteral("            <div class=\"form-check\">\r\n                <input class=\"form-check-input\" type=\"checkbox\" name=\"selectedTables\"");
                BeginWriteAttribute("value", " value=\"", 550, "\"", 560, 1);
                WriteAttributeValue("", 558, 
#nullable restore
#line (16,95)-(16,96) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\Database\Tables.cshtml"
t

#line default
#line hidden
#nullable disable
                , 558, 2, false);
                EndWriteAttribute();
                BeginWriteAttribute("id", " id=\"", 561, "\"", 572, 2);
                WriteAttributeValue("", 566, "tbl_", 566, 4, true);
                WriteAttributeValue("", 570, 
#nullable restore
#line (16,107)-(16,108) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\Database\Tables.cshtml"
t

#line default
#line hidden
#nullable disable
                , 570, 2, false);
                EndWriteAttribute();
                WriteLiteral(" ");
                Write(
#nullable restore
#line (16,112)-(16,149) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\Database\Tables.cshtml"
selected.Contains(t) ? "checked" : ""

#line default
#line hidden
#nullable disable
                );
                WriteLiteral(" />\r\n                <label class=\"form-check-label\"");
                BeginWriteAttribute("for", " for=\"", 666, "\"", 678, 2);
                WriteAttributeValue("", 672, "tbl_", 672, 4, true);
                WriteAttributeValue("", 676, 
#nullable restore
#line (17,59)-(17,60) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\Database\Tables.cshtml"
t

#line default
#line hidden
#nullable disable
                , 676, 2, false);
                EndWriteAttribute();
                WriteLiteral(">");
                Write(
#nullable restore
#line (17,63)-(17,64) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\Database\Tables.cshtml"
t

#line default
#line hidden
#nullable disable
                );
                WriteLiteral("</label>\r\n            </div>\r\n");
#nullable restore
#line (19,1)-(20,1) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\Database\Tables.cshtml"
        }

#line default
#line hidden
#nullable disable

                WriteLiteral("    </div>\r\n    <button type=\"submit\" class=\"btn btn-success\">Seçili Tabloları Yönet</button>\r\n");
            }
            );
            __Microsoft_AspNetCore_Mvc_TagHelpers_FormTagHelper = CreateTagHelper<global::Microsoft.AspNetCore.Mvc.TagHelpers.FormTagHelper>();
            __tagHelperExecutionContext.Add(__Microsoft_AspNetCore_Mvc_TagHelpers_FormTagHelper);
            __Microsoft_AspNetCore_Mvc_TagHelpers_RenderAtEndOfFormTagHelper = CreateTagHelper<global::Microsoft.AspNetCore.Mvc.TagHelpers.RenderAtEndOfFormTagHelper>();
            __tagHelperExecutionContext.Add(__Microsoft_AspNetCore_Mvc_TagHelpers_RenderAtEndOfFormTagHelper);
            __Microsoft_AspNetCore_Mvc_TagHelpers_FormTagHelper.Action = (string)__tagHelperAttribute_0.Value;
            __tagHelperExecutionContext.AddTagHelperAttribute(__tagHelperAttribute_0);
            __Microsoft_AspNetCore_Mvc_TagHelpers_FormTagHelper.Method = (string)__tagHelperAttribute_1.Value;
            __tagHelperExecutionContext.AddTagHelperAttribute(__tagHelperAttribute_1);
            await __tagHelperRunner.RunAsync(__tagHelperExecutionContext);
            if (!__tagHelperExecutionContext.Output.IsContentModified)
            {
                await __tagHelperExecutionContext.SetOutputContentAsync();
            }
            Write(__tagHelperExecutionContext.Output);
            __tagHelperExecutionContext = __tagHelperScopeManager.End();
            WriteLiteral("\r\n");
        }
        #pragma warning restore 1998
        #nullable restore
        [global::Microsoft.AspNetCore.Mvc.Razor.Internal.RazorInjectAttribute]
        public global::Microsoft.AspNetCore.Mvc.ViewFeatures.IModelExpressionProvider ModelExpressionProvider { get; private set; } = default!;
        #nullable disable
        #nullable restore
        [global::Microsoft.AspNetCore.Mvc.Razor.Internal.RazorInjectAttribute]
        public global::Microsoft.AspNetCore.Mvc.IUrlHelper Url { get; private set; } = default!;
        #nullable disable
        #nullable restore
        [global::Microsoft.AspNetCore.Mvc.Razor.Internal.RazorInjectAttribute]
        public global::Microsoft.AspNetCore.Mvc.IViewComponentHelper Component { get; private set; } = default!;
        #nullable disable
        #nullable restore
        [global::Microsoft.AspNetCore.Mvc.Razor.Internal.RazorInjectAttribute]
        public global::Microsoft.AspNetCore.Mvc.Rendering.IJsonHelper Json { get; private set; } = default!;
        #nullable disable
        #nullable restore
        [global::Microsoft.AspNetCore.Mvc.Razor.Internal.RazorInjectAttribute]
        public global::Microsoft.AspNetCore.Mvc.Rendering.IHtmlHelper<StajWebProjesi.Models.DbConnectionInfo> Html { get; private set; } = default!;
        #nullable disable
    }
}
#pragma warning restore 1591
ParseOptions.0.json��
�C:\Users\omer\Desktop\staj proje\StajWebProjesi\obj\Debug\net10.0\Microsoft.CodeAnalysis.Razor.Compiler\Microsoft.NET.Sdk.Razor.SourceGenerators.RazorSourceGenerator\Views/Home/Index_cshtml.g.cs��#pragma checksum "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\Home\Index.cshtml" "{8829d00f-11b8-4213-878b-770e8597ac16}" "dbed63a44116b0061279e6dd8846219669a50da90d0b3490143c66446b8ac336"
// <auto-generated/>
#pragma warning disable 1591
[assembly: global::Microsoft.AspNetCore.Razor.Hosting.RazorCompiledItemAttribute(typeof(AspNetCoreGeneratedDocument.Views_Home_Index), @"mvc.1.0.view", @"/Views/Home/Index.cshtml")]
namespace AspNetCoreGeneratedDocument
{
    #line default
    using global::System;
    using global::System.Collections.Generic;
    using global::System.Linq;
    using global::System.Threading.Tasks;
    using global::Microsoft.AspNetCore.Mvc;
    using global::Microsoft.AspNetCore.Mvc.Rendering;
    using global::Microsoft.AspNetCore.Mvc.ViewFeatures;
#nullable restore
#line (1,2)-(1,22) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\_ViewImports.cshtml"
using StajWebProjesi

#nullable disable
    ;
#nullable restore
#line (2,2)-(2,29) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\_ViewImports.cshtml"
using StajWebProjesi.Models

#nullable disable
    ;
    #line default
    #line hidden
    [global::Microsoft.AspNetCore.Razor.Hosting.RazorCompiledItemMetadataAttribute("Identifier", "/Views/Home/Index.cshtml")]
    [global::System.Runtime.CompilerServices.CreateNewOnMetadataUpdateAttribute]
    #nullable restore
    internal sealed class Views_Home_Index : global::Microsoft.AspNetCore.Mvc.Razor.RazorPage<
#nullable restore
#line (1,8)-(1,53) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\Home\Index.cshtml"
StajWebProjesi.Models.BatchSelectionViewModel

#line default
#line hidden
#nullable disable
    >
    #nullable disable
    {
        private static readonly global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute __tagHelperAttribute_0 = new global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute("value", "daily", global::Microsoft.AspNetCore.Razor.TagHelpers.HtmlAttributeValueStyle.DoubleQuotes);
        private static readonly global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute __tagHelperAttribute_1 = new global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute("value", "monthly", global::Microsoft.AspNetCore.Razor.TagHelpers.HtmlAttributeValueStyle.DoubleQuotes);
        private static readonly global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute __tagHelperAttribute_2 = new global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute("value", "yearly", global::Microsoft.AspNetCore.Razor.TagHelpers.HtmlAttributeValueStyle.DoubleQuotes);
        private static readonly global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute __tagHelperAttribute_3 = new global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute("rel", new global::Microsoft.AspNetCore.Html.HtmlString("stylesheet"), global::Microsoft.AspNetCore.Razor.TagHelpers.HtmlAttributeValueStyle.DoubleQuotes);
        private static readonly global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute __tagHelperAttribute_4 = new global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute("href", new global::Microsoft.AspNetCore.Html.HtmlString("~/css/charts.css"), global::Microsoft.AspNetCore.Razor.TagHelpers.HtmlAttributeValueStyle.DoubleQuotes);
        #line hidden
        #pragma warning disable 0649
        private global::Microsoft.AspNetCore.Razor.Runtime.TagHelpers.TagHelperExecutionContext __tagHelperExecutionContext;
        #pragma warning restore 0649
        private global::Microsoft.AspNetCore.Razor.Runtime.TagHelpers.TagHelperRunner __tagHelperRunner = new global::Microsoft.AspNetCore.Razor.Runtime.TagHelpers.TagHelperRunner();
        #pragma warning disable 0169
        private string __tagHelperStringValueBuffer;
        #pragma warning restore 0169
        private global::Microsoft.AspNetCore.Razor.Runtime.TagHelpers.TagHelperScopeManager __backed__tagHelperScopeManager = null;
        private global::Microsoft.AspNetCore.Razor.Runtime.TagHelpers.TagHelperScopeManager __tagHelperScopeManager
        {
            get
            {
                if (__backed__tagHelperScopeManager == null)
                {
                    __backed__tagHelperScopeManager = new global::Microsoft.AspNetCore.Razor.Runtime.TagHelpers.TagHelperScopeManager(StartTagHelperWritingScope, EndTagHelperWritingScope);
                }
                return __backed__tagHelperScopeManager;
            }
        }
        private global::Microsoft.AspNetCore.Mvc.TagHelpers.OptionTagHelper __Microsoft_AspNetCore_Mvc_TagHelpers_OptionTagHelper;
        private global::Microsoft.AspNetCore.Mvc.Razor.TagHelpers.UrlResolutionTagHelper __Microsoft_AspNetCore_Mvc_Razor_TagHelpers_UrlResolutionTagHelper;
        #pragma warning disable 1998
        public async override global::System.Threading.Tasks.Task ExecuteAsync()
        {
            WriteLiteral(@"<div class=""app-shell"">
    <div class=""workspace"">
        <div class=""control-panel"">
            <h3>Kontrol Merkezi</h3>

            <div class=""control-group"">
                <label for=""batchIdInput"">Batch ID</label>
                <div class=""d-flex gap-2"">
                    <div style=""position: relative; flex: 1;"">
                        <input id=""batchIdInput"" type=""text"" class=""form-control"" placeholder=""Batch ID girin veya seçin"" autocomplete=""off"" readonly />
                        <button id=""batchDropdownToggle"" type=""button"" style=""position: absolute; right: 8px; top: 50%; transform: translateY(-50%); background: none; border: none; cursor: pointer; color: #c8ff00; font-size: 14px; z-index: 2;"">
                            &#9660;
                        </button>
                    </div>
                    <button id=""btnLoadBatch"" class=""btn btn-primary btn-sm"" style=""white-space: nowrap;"">Yükle</button>
                </div>
                <!-- Custom Dropdown -->
             ");
            WriteLiteral(@"   <div id=""batchDropdown"" class=""custom-dropdown"" style=""display: none;"">
                    <div id=""batchDropdownSearch"" style=""padding: 8px 10px; border-bottom: 1px solid #333;"">
                        <input type=""text"" class=""form-control form-control-sm"" placeholder=""Batch ID ara..."" id=""batchSearchInput"" aria-label=""Batch ID ara"" style=""background: #111; color: #c8ff00; border: 1px solid #444; font-size: 12px;"" />
                    </div>
                    <div id=""batchDropdownList"" style=""max-height: 250px; overflow-y: auto;""></div>
                </div>
            </div>

            <div class=""control-group"">
                <span class=""d-block mb-2 font-weight-bold"">Grafik Widgetleri</span>
                <div class=""widget-selector"">
                    <div class=""form-check"">
                        <input class=""form-check-input category-toggle"" type=""checkbox"" value=""flow"" id=""widget_fl"" checked aria-label=""Akış (FL) grafik widget'ı"" />
                        <label class=""form-c");
            WriteLiteral(@"heck-label"" for=""widget_fl"">Akış (FL)</label>
                    </div>
                    <div class=""form-check"">
                        <input class=""form-check-input category-toggle"" type=""checkbox"" value=""temp"" id=""widget_temp"" checked aria-label=""Sıcaklık (TEMP) grafik widget'ı"" />
                        <label class=""form-check-label"" for=""widget_temp"">Sıcaklık (TEMP)</label>
                    </div>
                    <div class=""form-check"">
                        <input class=""form-check-input category-toggle"" type=""checkbox"" value=""pressure"" id=""widget_pressure"" checked aria-label=""Basınç (PRESSURE) grafik widget'ı"" />
                        <label class=""form-check-label"" for=""widget_pressure"">Basınç (PRESSURE)</label>
                    </div>
                    <div class=""form-check"">
                        <input class=""form-check-input category-toggle"" type=""checkbox"" value=""density"" id=""widget_density"" checked aria-label=""Yoğunluk (DENSITY) grafik widget'ı"" />
                   ");
            WriteLiteral(@"     <label class=""form-check-label"" for=""widget_density"">Yoğunluk (DENSITY)</label>
                    </div>
                </div>
            </div>

            <div class=""control-group"">
                <label for=""timeRangeSelect"">Veri Aralığı</label>
                <select id=""timeRangeSelect"" class=""form-control"" style=""background: #0a0a0a; color: #c8ff00; border: 1px solid #c8ff00;"">
                    ");
            __tagHelperExecutionContext = __tagHelperScopeManager.Begin("option", global::Microsoft.AspNetCore.Razor.TagHelpers.TagMode.StartTagAndEndTag, "dbed63a44116b0061279e6dd8846219669a50da90d0b3490143c66446b8ac3368802", async() => {
                WriteLiteral("Günlük");
            }
            );
            __Microsoft_AspNetCore_Mvc_TagHelpers_OptionTagHelper = CreateTagHelper<global::Microsoft.AspNetCore.Mvc.TagHelpers.OptionTagHelper>();
            __tagHelperExecutionContext.Add(__Microsoft_AspNetCore_Mvc_TagHelpers_OptionTagHelper);
            __Microsoft_AspNetCore_Mvc_TagHelpers_OptionTagHelper.Value = (string)__tagHelperAttribute_0.Value;
            __tagHelperExecutionContext.AddTagHelperAttribute(__tagHelperAttribute_0);
            await __tagHelperRunner.RunAsync(__tagHelperExecutionContext);
            if (!__tagHelperExecutionContext.Output.IsContentModified)
            {
                await __tagHelperExecutionContext.SetOutputContentAsync();
            }
            Write(__tagHelperExecutionContext.Output);
            __tagHelperExecutionContext = __tagHelperScopeManager.End();
            WriteLiteral("\n                    ");
            __tagHelperExecutionContext = __tagHelperScopeManager.Begin("option", global::Microsoft.AspNetCore.Razor.TagHelpers.TagMode.StartTagAndEndTag, "dbed63a44116b0061279e6dd8846219669a50da90d0b3490143c66446b8ac33610003", async() => {
                WriteLiteral("Aylık");
            }
            );
            __Microsoft_AspNetCore_Mvc_TagHelpers_OptionTagHelper = CreateTagHelper<global::Microsoft.AspNetCore.Mvc.TagHelpers.OptionTagHelper>();
            __tagHelperExecutionContext.Add(__Microsoft_AspNetCore_Mvc_TagHelpers_OptionTagHelper);
            __Microsoft_AspNetCore_Mvc_TagHelpers_OptionTagHelper.Value = (string)__tagHelperAttribute_1.Value;
            __tagHelperExecutionContext.AddTagHelperAttribute(__tagHelperAttribute_1);
            await __tagHelperRunner.RunAsync(__tagHelperExecutionContext);
            if (!__tagHelperExecutionContext.Output.IsContentModified)
            {
                await __tagHelperExecutionContext.SetOutputContentAsync();
            }
            Write(__tagHelperExecutionContext.Output);
            __tagHelperExecutionContext = __tagHelperScopeManager.End();
            WriteLiteral("\n                    ");
            __tagHelperExecutionContext = __tagHelperScopeManager.Begin("option", global::Microsoft.AspNetCore.Razor.TagHelpers.TagMode.StartTagAndEndTag, "dbed63a44116b0061279e6dd8846219669a50da90d0b3490143c66446b8ac33611204", async() => {
                WriteLiteral("Yıllık");
            }
            );
            __Microsoft_AspNetCore_Mvc_TagHelpers_OptionTagHelper = CreateTagHelper<global::Microsoft.AspNetCore.Mvc.TagHelpers.OptionTagHelper>();
            __tagHelperExecutionContext.Add(__Microsoft_AspNetCore_Mvc_TagHelpers_OptionTagHelper);
            __Microsoft_AspNetCore_Mvc_TagHelpers_OptionTagHelper.Value = (string)__tagHelperAttribute_2.Value;
            __tagHelperExecutionContext.AddTagHelperAttribute(__tagHelperAttribute_2);
            await __tagHelperRunner.RunAsync(__tagHelperExecutionContext);
            if (!__tagHelperExecutionContext.Output.IsContentModified)
            {
                await __tagHelperExecutionContext.SetOutputContentAsync();
            }
            Write(__tagHelperExecutionContext.Output);
            __tagHelperExecutionContext = __tagHelperScopeManager.End();
            WriteLiteral(@"
                </select>
            </div>

            <div class=""control-group"">
                <label for=""yearCountInput"">Son Kaç?</label>
                <input id=""yearCountInput"" type=""number"" class=""form-control"" value=""1"" min=""1"" max=""20"" style=""width: 80px; background: #0a0a0a; color: #c8ff00; border: 1px solid #c8ff00;"" />
                <small >Örnek: Günlük: Son 1gün, Aylık: Son 1 ay, Yıllık: Son 1 yıl</small>
            </div>

            <div class=""control-group"">
                <label for=""chartHeightSlider"">Tablo Boyutu</label>
                <div class=""d-flex align-items-center gap-2"">
                    <input id=""chartHeightSlider"" type=""range"" min=""50"" max=""500"" value=""190"" class=""form-range"" style=""accent-color: #c8ff00;"" />
                    <span id=""chartHeightValue"">190 px</span>
                </div>
            </div>

        </div>

        <div class=""paper-area"">
            <div class=""paper-sheet"">
                <!-- Üst Bilgi Şeridi -->
                <div");
            WriteLiteral(@" id=""reportHeader"" style=""display:none; background: #ffc107; padding: 4px 10px; border: 2px solid black; margin-bottom: 4px; border-radius: 2px;"">
                    <div style=""display: flex; justify-content: space-between; align-items: center; color: #000; font-weight: 600; font-size: 11px;"">
                        <span id=""headerBatchId"">Batch ID : —</span>
                        <span id=""headerDate"">—</span>
                    </div>
                </div>

                <div id=""widgetGrid"" class=""widget-grid empty""></div>

                <!-- GSV / Mass Karşılaştırma Tablosu -->
                <div id=""comparisonSection"" style=""display:none; margin-top: 6px;"">
                    <div style=""background: #ffc107; padding: 3px 8px; border: 2px solid black; border-bottom: none; border-radius: 2px 2px 0 0; font-weight: 600; font-size: 10px; color: #000;"">
                        Konşimento / Sayaç Karşılaştırması
                    </div>
                    <table id=""comparisonTable"" style=""wid");
            WriteLiteral(@"th: 100%; border-collapse: collapse; border: 2px solid black; font-size: 10px; color: #000;"">
                        <thead>
                            <tr>
                                <th style=""border: 2px solid black; padding: 3px 6px; background: #fff; width: 50px; color: #000;"">Tip</th>
                                <th style=""border: 2px solid black; padding: 3px 6px; background: #d4edda; color: #000;"">Konş.</th>
                                <th style=""border: 2px solid black; padding: 3px 6px; background: #d4edda; color: #000;"">Sayaç</th>
                                <th style=""border: 2px solid black; padding: 3px 6px; background: #d4edda; color: #000;"">Fark %</th>
                                <th style=""border: 2px solid black; padding: 3px 6px; background: #ffe0b2; color: #000;"">SahilTank</th>
                                <th style=""border: 2px solid black; padding: 3px 6px; background: #ffe0b2; color: #000;"">Fark %</th>
                            </tr>
                        <");
            WriteLiteral(@"/thead>
                        <tbody>
                            <tr>
                                <td style=""border: 2px solid black; padding: 3px 6px; font-weight: 600; color: #000;"">GSV</td>
                                <td id=""gsvKonsement"" style=""border: 2px solid black; padding: 3px 6px; background: #e8f5e9; text-align: center; color: #000;"">—</td>
                                <td id=""gsvMeter"" style=""border: 2px solid black; padding: 3px 6px; background: #e8f5e9; text-align: center; color: #000;"">—</td>
                                <td id=""gsvDiff"" style=""border: 2px solid black; padding: 3px 6px; background: #e8f5e9; text-align: center; color: #000;"">—</td>
                                <td id=""gsvSahil"" style=""border: 2px solid black; padding: 3px 6px; background: #fff3e0; text-align: center; color: #000;"">—</td>
                                <td id=""gsvSahilDiff"" style=""border: 2px solid black; padding: 3px 6px; background: #fff3e0; text-align: center; color: #000;"">—</td>
       ");
            WriteLiteral(@"                     </tr>
                            <tr>
                                <td style=""border: 2px solid black; padding: 3px 6px; font-weight: 600; color: #000;"">Mass</td>
                                <td id=""massKonsement"" style=""border: 2px solid black; padding: 3px 6px; background: #e8f5e9; text-align: center; color: #000;"">—</td>
                                <td id=""massMeter"" style=""border: 2px solid black; padding: 3px 6px; background: #e8f5e9; text-align: center; color: #000;"">—</td>
                                <td id=""massDiff"" style=""border: 2px solid black; padding: 3px 6px; background: #e8f5e9; text-align: center; color: #000;"">—</td>
                                <td id=""massSahil"" style=""border: 2px solid black; padding: 3px 6px; background: #fff3e0; text-align: center; color: #000;"">—</td>
                                <td id=""massSahilDiff"" style=""border: 2px solid black; padding: 3px 6px; background: #fff3e0; text-align: center; color: #000;"">—</td>
              ");
            WriteLiteral("              </tr>\n                        </tbody>\n                    </table>\n                </div>\n            </div>\n        </div>\n    </div>\n</div>\n\n<script src=\"https://cdn.jsdelivr.net/npm/chart.js\"></script>\n");
            __tagHelperExecutionContext = __tagHelperScopeManager.Begin("link", global::Microsoft.AspNetCore.Razor.TagHelpers.TagMode.SelfClosing, "dbed63a44116b0061279e6dd8846219669a50da90d0b3490143c66446b8ac33618020", async() => {
            }
            );
            __Microsoft_AspNetCore_Mvc_Razor_TagHelpers_UrlResolutionTagHelper = CreateTagHelper<global::Microsoft.AspNetCore.Mvc.Razor.TagHelpers.UrlResolutionTagHelper>();
            __tagHelperExecutionContext.Add(__Microsoft_AspNetCore_Mvc_Razor_TagHelpers_UrlResolutionTagHelper);
            __tagHelperExecutionContext.AddHtmlAttribute(__tagHelperAttribute_3);
            __tagHelperExecutionContext.AddHtmlAttribute(__tagHelperAttribute_4);
            await __tagHelperRunner.RunAsync(__tagHelperExecutionContext);
            if (!__tagHelperExecutionContext.Output.IsContentModified)
            {
                await __tagHelperExecutionContext.SetOutputContentAsync();
            }
            Write(__tagHelperExecutionContext.Output);
            __tagHelperExecutionContext = __tagHelperScopeManager.End();
            WriteLiteral(@"
<style>
    .summary-table {
        width: auto;
        border-collapse: collapse;
        font-size: 9px;
        margin-top: 4px;
    }
    .summary-table th, .summary-table td {
        border: 1px solid #ddd;
        padding: 2px 6px;
        text-align: center;
    }
    .summary-table th {
        background: #f5f5f5;
        font-weight: 600;
    }
    .editable-title {
        cursor: pointer;
        border: 1px dashed transparent;
        padding: 2px 4px;
        border-radius: 3px;
    }
    .editable-title:hover {
        border-color: #999;
        background: #fafafa;
    }
    .chart-card {
        position: relative;
        background: #fff;
        border: 1px solid #ddd;
        border-radius: 4px;
        overflow: hidden;
        box-sizing: border-box;
    }
    .widget-grid {
        display: flex;
        flex-wrap: wrap;
        gap: 4px;
    }
    .chart-canvas-wrapper {
        position: relative;
        width: 100%;
    }
    .editable-title {
        color: #000 !important;
 ");
            WriteLiteral(@"   }

    /* Tüm butonlar normal durumu */
    .btn-primary, .btn-secondary, .btn, #btnLoadBatch,
    .toolbar-btn, .modal-footer .btn-primary, .modal-footer .btn-secondary {
        background-color: #c8ff00 !important;
        border-color: #c8ff00 !important;
        color: #000 !important;
    }

    /* Tüm butonlar hover turuncu */
    .btn-primary:hover, .btn-secondary:hover, .btn:hover, #btnLoadBatch:hover,
    .toolbar-btn:hover, .modal-footer .btn-primary:hover, .modal-footer .btn-secondary:hover {
        background-color: #ffc107 !important;
        border-color: #ffc107 !important;
        color: #000 !important;
    }

    /* Widget checkbox renkleri */
    .category-toggle:checked {
        background-color: #c8ff00 !important;
        border-color: #c8ff00 !important;
    }
    .category-toggle:hover {
        border-color: #ffc107 !important;
    }
    .category-toggle:checked:hover {
        background-color: #ffc107 !important;
        border-color: #ffc107 !important;
    }
    /* Custom Ba");
            WriteLiteral(@"tch Dropdown Styles (Dark Theme) */
    .custom-dropdown {
        position: absolute;
        top: calc(100% + 2px);
        left: 0;
        width: 100%;
        min-width: 280px;
        z-index: 1050;
        background: #1a1a1a;
        border: 1px solid #c8ff00;
        border-radius: 6px;
        box-shadow: 0 4px 16px rgba(0,0,0,0.5);
    }
    #batchDropdownSearch {
        padding: 8px 10px !important;
        border-bottom: 1px solid #333 !important;
    }
    #batchDropdownSearch input {
        background: #111 !important;
        color: #c8ff00 !important;
        border: 1px solid #444 !important;
        border-radius: 4px !important;
        font-size: 12px;
    }
    #batchDropdownSearch input::placeholder {
        color: #666 !important;
    }
    #batchDropdownSearch input:focus {
        border-color: #c8ff00 !important;
        outline: none;
    }
    #batchDropdownList {
        max-height: 250px;
        overflow-y: auto;
    }
    #batchDropdownList::-webkit-scrollbar {
        widt");
            WriteLiteral(@"h: 6px;
    }
    #batchDropdownList::-webkit-scrollbar-track {
        background: #1a1a1a;
    }
    #batchDropdownList::-webkit-scrollbar-thumb {
        background: #444;
        border-radius: 3px;
    }
    .custom-dropdown .dropdown-item {
        padding: 8px 12px;
        cursor: pointer;
        font-size: 13px;
        border-bottom: 1px solid #2a2a2a;
        transition: background 0.15s;
        color: #ccc;
    }
    .custom-dropdown .dropdown-item:hover {
        background: #2a2a2a;
        color: #c8ff00;
    }
    .custom-dropdown .dropdown-item:last-child {
        border-bottom: none;
    }
    .custom-dropdown .dropdown-item .batch-id {
        font-weight: 700;
        color: #c8ff00;
    }
    .custom-dropdown .dropdown-item .batch-details {
        color: #888;
        font-size: 11px;
        margin-top: 2px;
    }
    #batchIdInput {
        cursor: pointer;
        padding-right: 30px;
    }
    ");
            WriteLiteral(@"@media print {
        .control-panel, #pdfSaveBtn, .toolbar-group .toolbar-btn:not(.toolbar-db) {
            display: none !important;
        }
        .paper-sheet {
            width: 210mm;
            padding: 15mm;
        }
        .chart-card {
            page-break-inside: avoid;
            margin-bottom: 8px;
        }
        .chart-card canvas {
            max-width: 100% !important;
            max-height: none !important;
        }
        .summary-table {
            page-break-inside: avoid;
        }
        #reportHeader, #comparisonSection {
            page-break-inside: avoid;
        }
    }
</style>
<script>
document.addEventListener('DOMContentLoaded', async function () {

    // --- Sabit Grafik Grupları ---
    // Legend sırası: idx 0 = solda, idx son = sağda
    // overplotting: order ile çizim sırası (yüksek order = altta)
    const chartGroups = {
        flow: {
            title: 'Akış (FL)',
            columns: ['FL', 'FL1', 'FL2', 'FL3'],
            colors: ['#0057b8', ");
            WriteLiteral(@"'#e67e22', '#27ae60', '#8e44ad'],
            strokeWidths: [4, 3, 2, 1.5]
        },
        temp: {
            title: 'Sıcaklık (TEMP)',
            columns: ['TEMP_DENS', 'TEMP1', 'TEMP2', 'TEMP3'],
            colors: ['#c0392b', '#e67e22', '#27ae60', '#8e44ad'],
            strokeWidths: [4, 3, 2, 1.5]
        },
        pressure: {
            title: 'Basınç (PRESSURE)',
            columns: ['SKID_INLET_PRESSURE', 'PRES1', 'PRES2', 'PRES3'],
            colors: ['#c0392b', '#e67e22', '#27ae60', '#8e44ad'],
            strokeWidths: [4, 3, 2, 1.5]
        },
        density: {
            title: 'Yoğunluk (DENSITY)',
            columns: ['DENSITY'],
            colors: ['#2c3e50'],
            strokeWidths: [4]
        }
    };

    let chartInstances = {};
    let currentChartHeight = 190;

    // --- Element Seçimleri ---
    const batchIdInput = document.getElementById('batchIdInput');
    const widgetGrid = document.getElementById('widgetGrid');
    const chartHeightSlider = document.getElementByI");
            WriteLiteral(@"d('chartHeightSlider');
    const chartHeightValue = document.getElementById('chartHeightValue');
    const reportHeader = document.getElementById('reportHeader');
    const comparisonSection = document.getElementById('comparisonSection');
    const batchDropdown = document.getElementById('batchDropdown');
    const batchDropdownToggle = document.getElementById('batchDropdownToggle');
    const batchDropdownList = document.getElementById('batchDropdownList');
    const batchSearchInput = document.getElementById('batchSearchInput');

    let allBatches = []; // Tüm batch listesi (yeni→eski)

    // --- Tablo Boyutu Slider ---
    chartHeightSlider.addEventListener('input', function () {
        currentChartHeight = this.value;
        chartHeightValue.textContent = this.value + ' px';
        document.querySelectorAll('.chart-canvas-wrapper').forEach(w => {
            w.style.height = this.value + 'px';
        });
        Object.values(chartInstances).forEach(chart => {
            if (chart) chart.resize();");
            WriteLiteral(@"
        });
    });

    // --- Widget Checkboxları ---
    document.querySelectorAll('.category-toggle').forEach(cb => {
        cb.addEventListener('change', function () {
            const group = this.value;
            const card = document.getElementById(`card_${group}`);
            if (card) {
                card.style.display = this.checked ? '' : 'none';
            }
            updateVisibleXLabels();
        });
    });

    // --- Dropdown Toggle ---
    function toggleDropdown() {
        const isOpen = batchDropdown.style.display === 'block';
        batchDropdown.style.display = isOpen ? 'none' : 'block';
        if (!isOpen) {
            batchSearchInput.value = '';
            renderDropdownItems(allBatches);
            batchSearchInput.focus();
        }
    }

    function closeDropdown() {
        batchDropdown.style.display = 'none';
    }

    function renderDropdownItems(batches) {
        batchDropdownList.innerHTML = '';
        if (batches.length === 0) {
            batchDropd");
            WriteLiteral(@"ownList.innerHTML = '<div style=""padding: 8px 12px; color: #888; font-size: 13px; text-align: center;"">Batch bulunamadı.</div>';
            return;
        }
        batches.forEach(batch => {
            const item = document.createElement('div');
            item.className = 'dropdown-item';
            item.dataset.batchId = batch.batchId;
            const dateStr = new Date(batch.batchDate).toLocaleString('tr-TR');
            item.innerHTML = `<div class=""batch-id"">${batch.batchId}</div><div class=""batch-details"">${batch.shipName || '—'} | ${batch.loadType || '—'} | ${dateStr}</div>`;
            item.addEventListener('click', function (e) {
                e.stopPropagation();
                const id = this.dataset.batchId;
                batchIdInput.value = id;
                sessionStorage.setItem('lastBatchId', id);
                closeDropdown();
                // Otomatik yükle
                loadChartData(parseInt(id));
            });
            batchDropdownList.appendChild(item);
    ");
            WriteLiteral(@"    });
    }

    // Dropdown toggle butonu
    batchDropdownToggle.addEventListener('click', function (e) {
        e.stopPropagation();
        toggleDropdown();
    });

    // Input'a tıklayınca dropdown aç
    batchIdInput.addEventListener('click', function (e) {
        e.stopPropagation();
        toggleDropdown();
    });

    // Arama inputu
    batchSearchInput.addEventListener('click', function (e) {
        e.stopPropagation();
    });

    batchSearchInput.addEventListener('input', function () {
        const query = this.value.toLowerCase().trim();
        if (query === '') {
            renderDropdownItems(allBatches);
        } else {
            const filtered = allBatches.filter(b =>
                b.batchId.toString().includes(query) ||
                (b.shipName && b.shipName.toLowerCase().includes(query)) ||
                (b.loadType && b.loadType.toLowerCase().includes(query))
            );
            renderDropdownItems(filtered);
        }
    });

    // Dışarı tıklayınca kapat");
            WriteLiteral(@"
    document.addEventListener('click', function (e) {
        if (!batchDropdown.contains(e.target) && e.target !== batchIdInput && e.target !== batchDropdownToggle) {
            closeDropdown();
        }
    });

    // --- Batch Load Button ---
    const btnLoadBatch = document.getElementById('btnLoadBatch');
    if (btnLoadBatch) {
        btnLoadBatch.addEventListener('click', function () {
            const val = parseInt(batchIdInput.value);
            if (!isNaN(val) && val > 0) {
                sessionStorage.setItem('lastBatchId', batchIdInput.value);
                loadChartData(val);
            } else {
                alert('Lütfen geçerli bir Batch ID girin.');
            }
        });
    }

    batchIdInput.addEventListener('keydown', function (e) {
        if (e.key === 'Enter') {
            e.preventDefault();
            btnLoadBatch.click();
        }
    });

    // --- Üst Bilgi Şeridini Güncelle ---
    function updateReportHeader(batchId) {
        const now = new Date();
     ");
            WriteLiteral(@"   const dateStr = now.toLocaleDateString('tr-TR');
        document.getElementById('headerBatchId').textContent = `Batch ID : ${batchId}`;
        document.getElementById('headerDate').textContent = dateStr;
        reportHeader.style.display = 'block';
    }

    // --- Batch Listesini Yükle ---
    async function loadBatches() {
        try {
            const response = await fetch('/Data/GetBatches');
            if (!response.ok) {
                const errText = await response.text().catch(() => '');
                console.error('GetBatches HTTP hatası:', response.status, response.statusText, errText);
                return;
            }
            const data = await response.json();

            if (data.error) {
                console.error('Batch yükleme hatası:', data.error);
                return;
            }

            if (data.batches) {
                // API zaten DESC sıralı döndürüyor (yeni→eski), doğrudan kullan
                allBatches = data.batches;
                renderDrop");
            WriteLiteral(@"downItems(allBatches);

                if (allBatches.length > 0) {
                    const savedBatchId = sessionStorage.getItem('lastBatchId');
                    if (savedBatchId && allBatches.some(b => b.batchId.toString() === savedBatchId)) {
                        batchIdInput.value = savedBatchId;
                        // F5 sonrası kaydedilmiş Batch ID ile otomatik yükle
                        loadChartData(parseInt(savedBatchId));
                    } else {
                        batchIdInput.value = allBatches[0].batchId;
                        // İlk açılışta ilk batch'i otomatik yükle
                        loadChartData(allBatches[0].batchId);
                    }
                }
            }
        } catch (error) {
            console.error('Batch yükleme hatası:', error);
        }
    }

    // --- Grafikleri Çiz ---
    async function loadChartData(batchId) {
        try {
            const allColumns = new Set();
            Object.values(chartGroups).forEach(g => g.column");
            WriteLiteral(@"s.forEach(c => allColumns.add(c)));
            const columnsStr = Array.from(allColumns).join(',');
            const timeRange = document.getElementById('timeRangeSelect').value;
            const yearCountInput = document.getElementById('yearCountInput');
            const yearCount = yearCountInput ? parseInt(yearCountInput.value) || 1 : 1;

            // Grafik verisini yükle
            const response = await fetch(`/Data/GetHistTrendByBatch?batchId=${batchId}&columns=${columnsStr}&timeRange=${timeRange}&yearCount=${yearCount}`);
            if (!response.ok) {
                console.error('GetHistTrendByBatch HTTP hatası:', response.status, response.statusText);
                return;
            }
            const data = await response.json();

            if (data.error) {
                console.error('Veri hatası:', data.error);
                return;
            }

            // GSV/Mass karşılaştırma verisini yükle
            loadComparisonData(batchId);

            // Üst bilgi şeridini ");
            WriteLiteral(@"güncelle
            updateReportHeader(batchId);

            renderAllCharts(data);
        } catch (error) {
            console.error('Grafik yükleme hatası:', error);
        }
    }

    // --- GSV / Mass Karşılaştırma Verisini Yükle ---
    async function loadComparisonData(batchId) {
        try {
            const response = await fetch(`/Data/GetBatchComparison?batchId=${batchId}`);
            if (!response.ok) {
                console.warn('GetBatchComparison HTTP hatası:', response.status);
                comparisonSection.style.display = 'none';
                return;
            }
            const data = await response.json();

            if (data.error) {
                console.warn('Karşılaştırma verisi hatası:', data.error);
                comparisonSection.style.display = 'none';
                return;
            }

            comparisonSection.style.display = 'block';

            // GSV satırı - veritabanındaki orijinal string değerleri olduğu gibi göster
            const gsvKo");
            WriteLiteral(@"nsStr = data.gsvKonsement || ""0"";
            const gsvMeterStr = data.gsvMeter || ""0"";
            const gsvKons = parseFloat(gsvKonsStr) || 0;
            const gsvMeter = parseFloat(gsvMeterStr) || 0;
            document.getElementById('gsvKonsement').textContent = gsvKonsStr;
            document.getElementById('gsvMeter').textContent = gsvMeterStr;
            if (gsvKons !== 0) {
                const gsvDiff = Math.abs(gsvKons - gsvMeter) / gsvKons * 100;
                document.getElementById('gsvDiff').textContent = gsvDiff.toFixed(3) + ' %';
            } else {
                document.getElementById('gsvDiff').textContent = '—';
            }

            // Mass satırı - veritabanındaki orijinal string değerleri olduğu gibi göster
            const massKonsStr = data.massKonsement || ""0"";
            const massMeterStr = data.massMeter || ""0"";
            const massKons = parseFloat(massKonsStr) || 0;
            const massMeter = parseFloat(massMeterStr) || 0;
            document.getElementBy");
            WriteLiteral(@"Id('massKonsement').textContent = massKonsStr;
            document.getElementById('massMeter').textContent = massMeterStr;
            if (massKons !== 0) {
                const massDiff = Math.abs(massKons - massMeter) / massKons * 100;
                document.getElementById('massDiff').textContent = massDiff.toFixed(3) + ' %';
            } else {
                document.getElementById('massDiff').textContent = '—';
            }
        } catch (error) {
            console.warn('Karşılaştırma verisi yükleme hatası:', error);
            comparisonSection.style.display = 'none';
        }
    }

    function renderAllCharts(data) {
        clearCharts();
        const height = currentChartHeight + 'px';

        Object.entries(chartGroups).forEach(([groupKey, group]) => {
            const card = document.createElement('section');
            card.className = 'chart-card';
            card.id = `card_${groupKey}`;
            card.style.cssText = 'position: relative; background: #fff; border: 1px solid");
            WriteLiteral(@" #ddd; border-radius: 4px; padding: 8px 12px 12px 12px; margin-bottom: 0;';
            const checkboxId = groupKey === 'flow' ? 'widget_fl' : `widget_${groupKey}`;
            const checkbox = document.getElementById(checkboxId);
            card.style.display = checkbox && checkbox.checked ? '' : 'none';

            // Düzenlenebilir Başlık
            const titleEl = document.createElement('div');
            titleEl.className = 'editable-title';
            titleEl.style.cssText = 'position: absolute; top: 4px; left: 6px; font-size: 12px; font-weight: bold; color: #000; background: rgba(255,255,255,0.7); padding: 1px 4px; border-radius: 2px; border: 1px dashed transparent; cursor: pointer; z-index: 5; line-height: 1.2;';
            titleEl.textContent = group.title;
            titleEl.addEventListener('dblclick', function () {
                const self = this;
                const input = document.createElement('input');
                input.type = 'text';
                input.value = self.textCont");
            WriteLiteral(@"ent;
                input.style.cssText = 'font-size: 13px; font-weight: bold; border: 1px solid #ccc; padding: 2px 6px; width: 180px;';
                input.addEventListener('blur', function () {
                    self.textContent = this.value || group.title;
                    this.replaceWith(self);
                });
                input.addEventListener('keydown', function (e) {
                    if (e.key === 'Enter') this.blur();
                });
                this.replaceWith(input);
                input.focus();
                input.select();
            });
            titleEl.addEventListener('mouseenter', function () {
                this.style.borderColor = '#999';
                this.style.background = '#fafafa';
            });
            titleEl.addEventListener('mouseleave', function () {
                if (this.tagName !== 'INPUT') {
                    this.style.borderColor = 'transparent';
                    this.style.background = 'rgba(255,255,255,0.9)';
           ");
            WriteLiteral(@"     }
            });
            card.appendChild(titleEl);

            // Canvas Wrapper
            const canvasWrapper = document.createElement('div');
            canvasWrapper.className = 'chart-canvas-wrapper';
            canvasWrapper.style.height = height;
            canvasWrapper.style.marginBottom = '0';
            card.appendChild(canvasWrapper);

            const canvas = document.createElement('canvas');
            canvas.className = 'chart-canvas';
            canvas.id = `chart_${groupKey}`;
            canvasWrapper.appendChild(canvas);

            // Özet Tablo (temp ve pressure için)
            if (groupKey === 'temp' || groupKey === 'pressure') {
                const summaryTable = document.createElement('table');
                summaryTable.className = 'summary-table';
                summaryTable.id = `summary_${groupKey}`;
                card.appendChild(summaryTable);
            }

            widgetGrid.appendChild(card);

            // Chart.js ile çizim
            con");
            WriteLiteral(@"st ctx = canvas.getContext('2d');
            const datasets = [];
            let availableCols = [];

            // LEGEND SIRALAMASI:
            // Chart.js'de legend, datasets array'indeki sırayla gösterilir.
            // Legend'da soldan sağa: FL(0), FL1(1), FL2(2), FL3(3) olması için
            // datasets'leri idx sırasına göre (artan) ekliyoruz.
            // OVERPLOTTING (z-order): 'order' property ile ayarlanır.
            // Yüksek order = altta çizilir, düşük order = üstte çizilir.
            // Yani idx 0 (FL, 4px kalın) → order yüksek (alta), idx son (FL3, 1.5px ince) → order 0 (üste).
            const totalCols = group.columns.length;
            group.columns.forEach((col, idx) => {
                if (data.series && data.series[col] && data.series[col].length > 0) {
                    availableCols.push(col);
                    datasets.push({
                        label: col,
                        data: data.series[col],
                        borderColor: group.colors[idx] |");
            WriteLiteral(@"| '#333',
                        tension: 0.15,
                        pointRadius: 0,
                        borderWidth: group.strokeWidths[idx] || 2,
                        order: totalCols - 1 - idx,  // idx 0 → en yüksek order (alta çizilir), idx son → 0 (üste çizilir)
                        fill: false
                    });
                }
            });

            if (datasets.length > 0) {
                chartInstances[groupKey] = new Chart(ctx, {
                    type: 'line',
                    data: {
                        labels: data.labels || [],
                        datasets: datasets
                    },
                    options: {
                        responsive: true,
                        maintainAspectRatio: false,
                        animation: { duration: 200 },
                        interaction: { mode: 'index', intersect: false },
                        layout: { padding: { top: 0, right: 0, bottom: 0, left: 0 } },
                        plugins:");
            WriteLiteral(@" { legend: { display: true, position: 'top', labels: { font: { size: 10 }, padding: 6 } } },
                        scales: {
                            x: {
                                offset: false,
                                ticks: { maxTicksLimit: 50, font: { size: 8 }, autoSkip: true, autoSkipPadding: 4, maxRotation: 90, minRotation: 45, padding: 0 },
                                grid: { display: true, tickLength: 0, offset: false },
                                border: { display: true, dash: [] }
                            },
                            y: {
                                ticks: { font: { size: 8 }, padding: 0 },
                                grid: { display: true },
                                border: { display: true }
                            }
                        }
                    }
                });

                if (groupKey === 'temp' || groupKey === 'pressure') {
                    fillSummaryTable(groupKey, data, availableCols);
        ");
            WriteLiteral(@"        }
            } else {
                canvasWrapper.innerHTML = '<p class=""text-muted p-2"">Bu grup için veri bulunamadı.</p>';
            }
        });
        // Dinamik X ekseni etiketleri: sadece en alttaki aktif grafiğin X etiketleri görünür
        updateVisibleXLabels();
    }

    // --- Dinamik X Ekseni Etiketleri ---
    // Sadece en alttaki (sonda) kalan aktif grafiğin X ekseni tarih/saat etiketleri görünür.
    // Diğer grafiklerin X etiketleri gizlidir.
    function updateVisibleXLabels() {
        const visibleCards = Array.from(widgetGrid.querySelectorAll('.chart-card'))
            .filter(c => c.style.display !== 'none');
        const lastCard = visibleCards.length > 0 ? visibleCards[visibleCards.length - 1] : null;

        Object.entries(chartInstances).forEach(([groupKey, chart]) => {
            if (!chart || !chart.options || !chart.options.scales || !chart.options.scales.x) return;
            const card = document.getElementById(`card_${groupKey}`);
            const isLastVi");
            WriteLiteral(@"sible = card && card === lastCard;
            chart.options.scales.x.ticks.display = isLastVisible;
            chart.options.scales.x.border.display = isLastVisible;
            chart.update();
        });
    }

    function fillSummaryTable(groupKey, data, columns) {
        const table = document.getElementById(`summary_${groupKey}`);
        if (!table || columns.length === 0) return;

        let html = '<thead><tr><th style=""padding:2px 6px;font-size:9px;"">Kolon</th><th style=""padding:2px 6px;font-size:9px;"">Min</th><th style=""padding:2px 6px;font-size:9px;"">Maks</th><th style=""padding:2px 6px;font-size:9px;"">Ort</th><th style=""padding:2px 6px;font-size:9px;"">İlk</th></tr></thead><tbody>';
        
        columns.forEach(col => {
            const values = (data.series[col] || []).filter(v => !isNaN(v));
            if (values.length === 0) return;
            
            const min = Math.min(...values);
            const max = Math.max(...values);
            const avg = values.reduce((a, b) => a +");
            WriteLiteral(@" b, 0) / values.length;
            const first = values[0]; // ASC sıralamada ilk kayıt = en eski veri

            html += `<tr>
                <td style=""padding:2px 6px;font-size:9px;"">${col}</td>
                <td style=""padding:2px 6px;font-size:9px;text-align:center;"">${min.toFixed(2)}</td>
                <td style=""padding:2px 6px;font-size:9px;text-align:center;"">${max.toFixed(2)}</td>
                <td style=""padding:2px 6px;font-size:9px;text-align:center;"">${avg.toFixed(2)}</td>
                <td style=""padding:2px 6px;font-size:9px;text-align:center;"">${first.toFixed(2)}</td>
            </tr>`;
        });

        html += '</tbody>';
        table.style.cssText = 'width:auto;margin-top:4px;border-collapse:collapse;font-size:9px;';
        table.innerHTML = html;
    }

    function clearCharts() {
        Object.values(chartInstances).forEach(c => c.destroy());
        chartInstances = {};
        if (widgetGrid) widgetGrid.innerHTML = '';
    }

    // --- Event Listeners ---
    const");
            WriteLiteral(@" timeRangeSelect = document.getElementById('timeRangeSelect');
    if (timeRangeSelect) {
        // F5 sonrası restore
        const savedTimeRange = sessionStorage.getItem('lastTimeRange');
        if (savedTimeRange) timeRangeSelect.value = savedTimeRange;

        timeRangeSelect.addEventListener('change', function() {
            sessionStorage.setItem('lastTimeRange', this.value);
            const currentBatchId = document.getElementById('batchIdInput').value;
            if (currentBatchId) {
                loadChartData(currentBatchId);
            }
        });
    }

    const yearCountInput = document.getElementById('yearCountInput');
    if (yearCountInput) {
        // F5 sonrası restore
        const savedYearCount = sessionStorage.getItem('lastYearCount');
        if (savedYearCount) yearCountInput.value = savedYearCount;

        yearCountInput.addEventListener('change', function() {
            sessionStorage.setItem('lastYearCount', this.value);
            const currentBatchId = document.");
            WriteLiteral(@"getElementById('batchIdInput').value;
            if (currentBatchId) {
                loadChartData(currentBatchId);
            }
        });
    }

    // --- Başlat ---
    // loadBatches içinde otomatik yüklemesi zaten var (session veya ilk batch)
    await loadBatches();

    // --- Bağlantı Durumunu Göster ---
    fetch('/Database/GetConnectionStatus')
        .then(r => r.json())
        .then(data => {
            if (!data.connected) {
                console.log('Veritabanına bağlı değil. Lütfen bağlantı yapın.');
            }
        })
        .catch(() => {});

    // --- Global DB Connect Event Listener (""Veritabanına bağlan"" sonrası otomatik yükleme) ---
    document.addEventListener('dbConnected', function () {
        loadBatches();
    });
});
</script>
");
        }
        #pragma warning restore 1998
        #nullable restore
        [global::Microsoft.AspNetCore.Mvc.Razor.Internal.RazorInjectAttribute]
        public global::Microsoft.AspNetCore.Mvc.ViewFeatures.IModelExpressionProvider ModelExpressionProvider { get; private set; } = default!;
        #nullable disable
        #nullable restore
        [global::Microsoft.AspNetCore.Mvc.Razor.Internal.RazorInjectAttribute]
        public global::Microsoft.AspNetCore.Mvc.IUrlHelper Url { get; private set; } = default!;
        #nullable disable
        #nullable restore
        [global::Microsoft.AspNetCore.Mvc.Razor.Internal.RazorInjectAttribute]
        public global::Microsoft.AspNetCore.Mvc.IViewComponentHelper Component { get; private set; } = default!;
        #nullable disable
        #nullable restore
        [global::Microsoft.AspNetCore.Mvc.Razor.Internal.RazorInjectAttribute]
        public global::Microsoft.AspNetCore.Mvc.Rendering.IJsonHelper Json { get; private set; } = default!;
        #nullable disable
        #nullable restore
        [global::Microsoft.AspNetCore.Mvc.Razor.Internal.RazorInjectAttribute]
        public global::Microsoft.AspNetCore.Mvc.Rendering.IHtmlHelper<StajWebProjesi.Models.BatchSelectionViewModel> Html { get; private set; } = default!;
        #nullable disable
    }
}
#pragma warning restore 1591
ParseOptions.0.json�(
�C:\Users\omer\Desktop\staj proje\StajWebProjesi\obj\Debug\net10.0\Microsoft.CodeAnalysis.Razor.Compiler\Microsoft.NET.Sdk.Razor.SourceGenerators.RazorSourceGenerator\Views/Shared/Error_cshtml.g.cs�&#pragma checksum "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\Shared\Error.cshtml" "{8829d00f-11b8-4213-878b-770e8597ac16}" "5dbf98b6b9394ad78206edce40cab1d7a238aa69cfefa41bab0ebc6aa22488aa"
// <auto-generated/>
#pragma warning disable 1591
[assembly: global::Microsoft.AspNetCore.Razor.Hosting.RazorCompiledItemAttribute(typeof(AspNetCoreGeneratedDocument.Views_Shared_Error), @"mvc.1.0.view", @"/Views/Shared/Error.cshtml")]
namespace AspNetCoreGeneratedDocument
{
    #line default
    using global::System;
    using global::System.Collections.Generic;
    using global::System.Linq;
    using global::System.Threading.Tasks;
    using global::Microsoft.AspNetCore.Mvc;
    using global::Microsoft.AspNetCore.Mvc.Rendering;
    using global::Microsoft.AspNetCore.Mvc.ViewFeatures;
#nullable restore
#line (1,2)-(1,22) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\_ViewImports.cshtml"
using StajWebProjesi

#nullable disable
    ;
#nullable restore
#line (2,2)-(2,29) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\_ViewImports.cshtml"
using StajWebProjesi.Models

#nullable disable
    ;
    #line default
    #line hidden
    [global::Microsoft.AspNetCore.Razor.Hosting.RazorCompiledItemMetadataAttribute("Identifier", "/Views/Shared/Error.cshtml")]
    [global::System.Runtime.CompilerServices.CreateNewOnMetadataUpdateAttribute]
    #nullable restore
    internal sealed class Views_Shared_Error : global::Microsoft.AspNetCore.Mvc.Razor.RazorPage<
#nullable restore
#line (1,8)-(1,22) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\Shared\Error.cshtml"
ErrorViewModel

#line default
#line hidden
#nullable disable
    >
    #nullable disable
    {
        #pragma warning disable 1998
        public async override global::System.Threading.Tasks.Task ExecuteAsync()
        {
#nullable restore
#line (2,3)-(4,1) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\Shared\Error.cshtml"

    ViewData["Title"] = "Error";

#line default
#line hidden
#nullable disable

            WriteLiteral("\r\n<h1 class=\"text-danger\">Error.</h1>\r\n<h2 class=\"text-danger\">An error occurred while processing your request.</h2>\r\n\r\n");
#nullable restore
#line (9,2)-(11,1) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\Shared\Error.cshtml"
if (Model.ShowRequestId)
{

#line default
#line hidden
#nullable disable

            WriteLiteral("    <p>\r\n        <strong>Request ID:</strong> <code>");
            Write(
#nullable restore
#line (12,45)-(12,60) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\Shared\Error.cshtml"
Model.RequestId

#line default
#line hidden
#nullable disable
            );
            WriteLiteral("</code>\r\n    </p>\r\n");
#nullable restore
#line (14,1)-(15,1) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\Shared\Error.cshtml"
}

#line default
#line hidden
#nullable disable

            WriteLiteral(@"
<h3>Development Mode</h3>
<p>
    Swapping to <strong>Development</strong> environment will display more detailed information about the error that occurred.
</p>
<p>
    <strong>The Development environment shouldn't be enabled for deployed applications.</strong>
    It can result in displaying sensitive information from exceptions to end users.
    For local debugging, enable the <strong>Development</strong> environment by setting the <strong>ASPNETCORE_ENVIRONMENT</strong> environment variable to <strong>Development</strong>
    and restarting the app.
</p>
");
        }
        #pragma warning restore 1998
        #nullable restore
        [global::Microsoft.AspNetCore.Mvc.Razor.Internal.RazorInjectAttribute]
        public global::Microsoft.AspNetCore.Mvc.ViewFeatures.IModelExpressionProvider ModelExpressionProvider { get; private set; } = default!;
        #nullable disable
        #nullable restore
        [global::Microsoft.AspNetCore.Mvc.Razor.Internal.RazorInjectAttribute]
        public global::Microsoft.AspNetCore.Mvc.IUrlHelper Url { get; private set; } = default!;
        #nullable disable
        #nullable restore
        [global::Microsoft.AspNetCore.Mvc.Razor.Internal.RazorInjectAttribute]
        public global::Microsoft.AspNetCore.Mvc.IViewComponentHelper Component { get; private set; } = default!;
        #nullable disable
        #nullable restore
        [global::Microsoft.AspNetCore.Mvc.Razor.Internal.RazorInjectAttribute]
        public global::Microsoft.AspNetCore.Mvc.Rendering.IJsonHelper Json { get; private set; } = default!;
        #nullable disable
        #nullable restore
        [global::Microsoft.AspNetCore.Mvc.Razor.Internal.RazorInjectAttribute]
        public global::Microsoft.AspNetCore.Mvc.Rendering.IHtmlHelper<ErrorViewModel> Html { get; private set; } = default!;
        #nullable disable
    }
}
#pragma warning restore 1591
ParseOptions.0.json�;
�C:\Users\omer\Desktop\staj proje\StajWebProjesi\obj\Debug\net10.0\Microsoft.CodeAnalysis.Razor.Compiler\Microsoft.NET.Sdk.Razor.SourceGenerators.RazorSourceGenerator\Views/Shared/_ValidationScriptsPartial_cshtml.g.cs�9#pragma checksum "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\Shared\_ValidationScriptsPartial.cshtml" "{8829d00f-11b8-4213-878b-770e8597ac16}" "574f31f5a9a43cd72f4e0bc199fffdb27204b0d0b537ac9cd5fad49d8203dfd5"
// <auto-generated/>
#pragma warning disable 1591
[assembly: global::Microsoft.AspNetCore.Razor.Hosting.RazorCompiledItemAttribute(typeof(AspNetCoreGeneratedDocument.Views_Shared__ValidationScriptsPartial), @"mvc.1.0.view", @"/Views/Shared/_ValidationScriptsPartial.cshtml")]
namespace AspNetCoreGeneratedDocument
{
    #line default
    using global::System;
    using global::System.Collections.Generic;
    using global::System.Linq;
    using global::System.Threading.Tasks;
    using global::Microsoft.AspNetCore.Mvc;
    using global::Microsoft.AspNetCore.Mvc.Rendering;
    using global::Microsoft.AspNetCore.Mvc.ViewFeatures;
#nullable restore
#line (1,2)-(1,22) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\_ViewImports.cshtml"
using StajWebProjesi

#nullable disable
    ;
#nullable restore
#line (2,2)-(2,29) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\_ViewImports.cshtml"
using StajWebProjesi.Models

#nullable disable
    ;
    #line default
    #line hidden
    [global::Microsoft.AspNetCore.Razor.Hosting.RazorCompiledItemMetadataAttribute("Identifier", "/Views/Shared/_ValidationScriptsPartial.cshtml")]
    [global::System.Runtime.CompilerServices.CreateNewOnMetadataUpdateAttribute]
    #nullable restore
    internal sealed class Views_Shared__ValidationScriptsPartial : global::Microsoft.AspNetCore.Mvc.Razor.RazorPage<dynamic>
    #nullable disable
    {
        private static readonly global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute __tagHelperAttribute_0 = new global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute("src", new global::Microsoft.AspNetCore.Html.HtmlString("~/lib/jquery-validation/dist/jquery.validate.min.js"), global::Microsoft.AspNetCore.Razor.TagHelpers.HtmlAttributeValueStyle.DoubleQuotes);
        private static readonly global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute __tagHelperAttribute_1 = new global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute("src", new global::Microsoft.AspNetCore.Html.HtmlString("~/lib/jquery-validation-unobtrusive/dist/jquery.validate.unobtrusive.min.js"), global::Microsoft.AspNetCore.Razor.TagHelpers.HtmlAttributeValueStyle.DoubleQuotes);
        #line hidden
        #pragma warning disable 0649
        private global::Microsoft.AspNetCore.Razor.Runtime.TagHelpers.TagHelperExecutionContext __tagHelperExecutionContext;
        #pragma warning restore 0649
        private global::Microsoft.AspNetCore.Razor.Runtime.TagHelpers.TagHelperRunner __tagHelperRunner = new global::Microsoft.AspNetCore.Razor.Runtime.TagHelpers.TagHelperRunner();
        #pragma warning disable 0169
        private string __tagHelperStringValueBuffer;
        #pragma warning restore 0169
        private global::Microsoft.AspNetCore.Razor.Runtime.TagHelpers.TagHelperScopeManager __backed__tagHelperScopeManager = null;
        private global::Microsoft.AspNetCore.Razor.Runtime.TagHelpers.TagHelperScopeManager __tagHelperScopeManager
        {
            get
            {
                if (__backed__tagHelperScopeManager == null)
                {
                    __backed__tagHelperScopeManager = new global::Microsoft.AspNetCore.Razor.Runtime.TagHelpers.TagHelperScopeManager(StartTagHelperWritingScope, EndTagHelperWritingScope);
                }
                return __backed__tagHelperScopeManager;
            }
        }
        private global::Microsoft.AspNetCore.Mvc.Razor.TagHelpers.UrlResolutionTagHelper __Microsoft_AspNetCore_Mvc_Razor_TagHelpers_UrlResolutionTagHelper;
        #pragma warning disable 1998
        public async override global::System.Threading.Tasks.Task ExecuteAsync()
        {
            __tagHelperExecutionContext = __tagHelperScopeManager.Begin("script", global::Microsoft.AspNetCore.Razor.TagHelpers.TagMode.StartTagAndEndTag, "574f31f5a9a43cd72f4e0bc199fffdb27204b0d0b537ac9cd5fad49d8203dfd54020", async() => {
            }
            );
            __Microsoft_AspNetCore_Mvc_Razor_TagHelpers_UrlResolutionTagHelper = CreateTagHelper<global::Microsoft.AspNetCore.Mvc.Razor.TagHelpers.UrlResolutionTagHelper>();
            __tagHelperExecutionContext.Add(__Microsoft_AspNetCore_Mvc_Razor_TagHelpers_UrlResolutionTagHelper);
            __tagHelperExecutionContext.AddHtmlAttribute(__tagHelperAttribute_0);
            await __tagHelperRunner.RunAsync(__tagHelperExecutionContext);
            if (!__tagHelperExecutionContext.Output.IsContentModified)
            {
                await __tagHelperExecutionContext.SetOutputContentAsync();
            }
            Write(__tagHelperExecutionContext.Output);
            __tagHelperExecutionContext = __tagHelperScopeManager.End();
            WriteLiteral("\r\n");
            __tagHelperExecutionContext = __tagHelperScopeManager.Begin("script", global::Microsoft.AspNetCore.Razor.TagHelpers.TagMode.StartTagAndEndTag, "574f31f5a9a43cd72f4e0bc199fffdb27204b0d0b537ac9cd5fad49d8203dfd55083", async() => {
            }
            );
            __Microsoft_AspNetCore_Mvc_Razor_TagHelpers_UrlResolutionTagHelper = CreateTagHelper<global::Microsoft.AspNetCore.Mvc.Razor.TagHelpers.UrlResolutionTagHelper>();
            __tagHelperExecutionContext.Add(__Microsoft_AspNetCore_Mvc_Razor_TagHelpers_UrlResolutionTagHelper);
            __tagHelperExecutionContext.AddHtmlAttribute(__tagHelperAttribute_1);
            await __tagHelperRunner.RunAsync(__tagHelperExecutionContext);
            if (!__tagHelperExecutionContext.Output.IsContentModified)
            {
                await __tagHelperExecutionContext.SetOutputContentAsync();
            }
            Write(__tagHelperExecutionContext.Output);
            __tagHelperExecutionContext = __tagHelperScopeManager.End();
            WriteLiteral("\r\n");
        }
        #pragma warning restore 1998
        #nullable restore
        [global::Microsoft.AspNetCore.Mvc.Razor.Internal.RazorInjectAttribute]
        public global::Microsoft.AspNetCore.Mvc.ViewFeatures.IModelExpressionProvider ModelExpressionProvider { get; private set; } = default!;
        #nullable disable
        #nullable restore
        [global::Microsoft.AspNetCore.Mvc.Razor.Internal.RazorInjectAttribute]
        public global::Microsoft.AspNetCore.Mvc.IUrlHelper Url { get; private set; } = default!;
        #nullable disable
        #nullable restore
        [global::Microsoft.AspNetCore.Mvc.Razor.Internal.RazorInjectAttribute]
        public global::Microsoft.AspNetCore.Mvc.IViewComponentHelper Component { get; private set; } = default!;
        #nullable disable
        #nullable restore
        [global::Microsoft.AspNetCore.Mvc.Razor.Internal.RazorInjectAttribute]
        public global::Microsoft.AspNetCore.Mvc.Rendering.IJsonHelper Json { get; private set; } = default!;
        #nullable disable
        #nullable restore
        [global::Microsoft.AspNetCore.Mvc.Razor.Internal.RazorInjectAttribute]
        public global::Microsoft.AspNetCore.Mvc.Rendering.IHtmlHelper<dynamic> Html { get; private set; } = default!;
        #nullable disable
    }
}
#pragma warning restore 1591
ParseOptions.0.json�
�C:\Users\omer\Desktop\staj proje\StajWebProjesi\obj\Debug\net10.0\Microsoft.CodeAnalysis.Razor.Compiler\Microsoft.NET.Sdk.Razor.SourceGenerators.RazorSourceGenerator\Views/_ViewImports_cshtml.g.cs�#pragma checksum "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\_ViewImports.cshtml" "{8829d00f-11b8-4213-878b-770e8597ac16}" "0e7eac282cc79bdff2d0073c77204497a9d665f5cf643443bc0663965fcb8151"
// <auto-generated/>
#pragma warning disable 1591
[assembly: global::Microsoft.AspNetCore.Razor.Hosting.RazorCompiledItemAttribute(typeof(AspNetCoreGeneratedDocument.Views__ViewImports), @"mvc.1.0.view", @"/Views/_ViewImports.cshtml")]
namespace AspNetCoreGeneratedDocument
{
    #line default
    using global::System;
    using global::System.Collections.Generic;
    using global::System.Linq;
    using global::System.Threading.Tasks;
    using global::Microsoft.AspNetCore.Mvc;
    using global::Microsoft.AspNetCore.Mvc.Rendering;
    using global::Microsoft.AspNetCore.Mvc.ViewFeatures;
#nullable restore
#line (1,2)-(1,22) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\_ViewImports.cshtml"
using StajWebProjesi

#nullable disable
    ;
#nullable restore
#line (2,2)-(2,29) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\_ViewImports.cshtml"
using StajWebProjesi.Models

#nullable disable
    ;
    #line default
    #line hidden
    [global::Microsoft.AspNetCore.Razor.Hosting.RazorCompiledItemMetadataAttribute("Identifier", "/Views/_ViewImports.cshtml")]
    [global::System.Runtime.CompilerServices.CreateNewOnMetadataUpdateAttribute]
    #nullable restore
    internal sealed class Views__ViewImports : global::Microsoft.AspNetCore.Mvc.Razor.RazorPage<dynamic>
    #nullable disable
    {
        #pragma warning disable 1998
        public async override global::System.Threading.Tasks.Task ExecuteAsync()
        {
        }
        #pragma warning restore 1998
        #nullable restore
        [global::Microsoft.AspNetCore.Mvc.Razor.Internal.RazorInjectAttribute]
        public global::Microsoft.AspNetCore.Mvc.ViewFeatures.IModelExpressionProvider ModelExpressionProvider { get; private set; } = default!;
        #nullable disable
        #nullable restore
        [global::Microsoft.AspNetCore.Mvc.Razor.Internal.RazorInjectAttribute]
        public global::Microsoft.AspNetCore.Mvc.IUrlHelper Url { get; private set; } = default!;
        #nullable disable
        #nullable restore
        [global::Microsoft.AspNetCore.Mvc.Razor.Internal.RazorInjectAttribute]
        public global::Microsoft.AspNetCore.Mvc.IViewComponentHelper Component { get; private set; } = default!;
        #nullable disable
        #nullable restore
        [global::Microsoft.AspNetCore.Mvc.Razor.Internal.RazorInjectAttribute]
        public global::Microsoft.AspNetCore.Mvc.Rendering.IJsonHelper Json { get; private set; } = default!;
        #nullable disable
        #nullable restore
        [global::Microsoft.AspNetCore.Mvc.Razor.Internal.RazorInjectAttribute]
        public global::Microsoft.AspNetCore.Mvc.Rendering.IHtmlHelper<dynamic> Html { get; private set; } = default!;
        #nullable disable
    }
}
#pragma warning restore 1591
ParseOptions.0.json�
�C:\Users\omer\Desktop\staj proje\StajWebProjesi\obj\Debug\net10.0\Microsoft.CodeAnalysis.Razor.Compiler\Microsoft.NET.Sdk.Razor.SourceGenerators.RazorSourceGenerator\Views/_ViewStart_cshtml.g.cs�#pragma checksum "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\_ViewStart.cshtml" "{8829d00f-11b8-4213-878b-770e8597ac16}" "47e02b4da20d198892b7b1b00b12944068797c438ef2e82d20ff70b4d56bad39"
// <auto-generated/>
#pragma warning disable 1591
[assembly: global::Microsoft.AspNetCore.Razor.Hosting.RazorCompiledItemAttribute(typeof(AspNetCoreGeneratedDocument.Views__ViewStart), @"mvc.1.0.view", @"/Views/_ViewStart.cshtml")]
namespace AspNetCoreGeneratedDocument
{
    #line default
    using global::System;
    using global::System.Collections.Generic;
    using global::System.Linq;
    using global::System.Threading.Tasks;
    using global::Microsoft.AspNetCore.Mvc;
    using global::Microsoft.AspNetCore.Mvc.Rendering;
    using global::Microsoft.AspNetCore.Mvc.ViewFeatures;
#nullable restore
#line (1,2)-(1,22) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\_ViewImports.cshtml"
using StajWebProjesi

#nullable disable
    ;
#nullable restore
#line (2,2)-(2,29) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\_ViewImports.cshtml"
using StajWebProjesi.Models

#nullable disable
    ;
    #line default
    #line hidden
    [global::Microsoft.AspNetCore.Razor.Hosting.RazorCompiledItemMetadataAttribute("Identifier", "/Views/_ViewStart.cshtml")]
    [global::System.Runtime.CompilerServices.CreateNewOnMetadataUpdateAttribute]
    #nullable restore
    internal sealed class Views__ViewStart : global::Microsoft.AspNetCore.Mvc.Razor.RazorPage<dynamic>
    #nullable disable
    {
        #pragma warning disable 1998
        public async override global::System.Threading.Tasks.Task ExecuteAsync()
        {
#nullable restore
#line (1,3)-(3,1) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\_ViewStart.cshtml"

    Layout = "_Layout";

#line default
#line hidden
#nullable disable

        }
        #pragma warning restore 1998
        #nullable restore
        [global::Microsoft.AspNetCore.Mvc.Razor.Internal.RazorInjectAttribute]
        public global::Microsoft.AspNetCore.Mvc.ViewFeatures.IModelExpressionProvider ModelExpressionProvider { get; private set; } = default!;
        #nullable disable
        #nullable restore
        [global::Microsoft.AspNetCore.Mvc.Razor.Internal.RazorInjectAttribute]
        public global::Microsoft.AspNetCore.Mvc.IUrlHelper Url { get; private set; } = default!;
        #nullable disable
        #nullable restore
        [global::Microsoft.AspNetCore.Mvc.Razor.Internal.RazorInjectAttribute]
        public global::Microsoft.AspNetCore.Mvc.IViewComponentHelper Component { get; private set; } = default!;
        #nullable disable
        #nullable restore
        [global::Microsoft.AspNetCore.Mvc.Razor.Internal.RazorInjectAttribute]
        public global::Microsoft.AspNetCore.Mvc.Rendering.IJsonHelper Json { get; private set; } = default!;
        #nullable disable
        #nullable restore
        [global::Microsoft.AspNetCore.Mvc.Razor.Internal.RazorInjectAttribute]
        public global::Microsoft.AspNetCore.Mvc.Rendering.IHtmlHelper<dynamic> Html { get; private set; } = default!;
        #nullable disable
    }
}
#pragma warning restore 1591
ParseOptions.0.json��
�C:\Users\omer\Desktop\staj proje\StajWebProjesi\obj\Debug\net10.0\Microsoft.CodeAnalysis.Razor.Compiler\Microsoft.NET.Sdk.Razor.SourceGenerators.RazorSourceGenerator\Views/Shared/_Layout_cshtml.g.cs��#pragma checksum "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\Shared\_Layout.cshtml" "{8829d00f-11b8-4213-878b-770e8597ac16}" "de5807ea14a7b924fdda14116d2dd2fcb3b926490b36b03cbccaa072df8c12dc"
// <auto-generated/>
#pragma warning disable 1591
[assembly: global::Microsoft.AspNetCore.Razor.Hosting.RazorCompiledItemAttribute(typeof(AspNetCoreGeneratedDocument.Views_Shared__Layout), @"mvc.1.0.view", @"/Views/Shared/_Layout.cshtml")]
namespace AspNetCoreGeneratedDocument
{
    #line default
    using global::System;
    using global::System.Collections.Generic;
    using global::System.Linq;
    using global::System.Threading.Tasks;
    using global::Microsoft.AspNetCore.Mvc;
    using global::Microsoft.AspNetCore.Mvc.Rendering;
    using global::Microsoft.AspNetCore.Mvc.ViewFeatures;
#nullable restore
#line (1,2)-(1,22) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\_ViewImports.cshtml"
using StajWebProjesi

#nullable disable
    ;
#nullable restore
#line (2,2)-(2,29) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\_ViewImports.cshtml"
using StajWebProjesi.Models

#nullable disable
    ;
    #line default
    #line hidden
    [global::Microsoft.AspNetCore.Razor.Hosting.RazorCompiledItemMetadataAttribute("Identifier", "/Views/Shared/_Layout.cshtml")]
    [global::System.Runtime.CompilerServices.CreateNewOnMetadataUpdateAttribute]
    #nullable restore
    internal sealed class Views_Shared__Layout : global::Microsoft.AspNetCore.Mvc.Razor.RazorPage<dynamic>
    #nullable disable
    {
        private static readonly global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute __tagHelperAttribute_0 = new global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute("type", "importmap", global::Microsoft.AspNetCore.Razor.TagHelpers.HtmlAttributeValueStyle.DoubleQuotes);
        private static readonly global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute __tagHelperAttribute_1 = new global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute("rel", new global::Microsoft.AspNetCore.Html.HtmlString("stylesheet"), global::Microsoft.AspNetCore.Razor.TagHelpers.HtmlAttributeValueStyle.DoubleQuotes);
        private static readonly global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute __tagHelperAttribute_2 = new global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute("href", new global::Microsoft.AspNetCore.Html.HtmlString("~/lib/bootstrap/dist/css/bootstrap.min.css"), global::Microsoft.AspNetCore.Razor.TagHelpers.HtmlAttributeValueStyle.DoubleQuotes);
        private static readonly global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute __tagHelperAttribute_3 = new global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute("href", "~/css/site.css", global::Microsoft.AspNetCore.Razor.TagHelpers.HtmlAttributeValueStyle.DoubleQuotes);
        private static readonly global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute __tagHelperAttribute_4 = new global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute("href", "~/StajWebProjesi.styles.css", global::Microsoft.AspNetCore.Razor.TagHelpers.HtmlAttributeValueStyle.DoubleQuotes);
        private static readonly global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute __tagHelperAttribute_5 = new global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute("class", new global::Microsoft.AspNetCore.Html.HtmlString("navbar-brand"), global::Microsoft.AspNetCore.Razor.TagHelpers.HtmlAttributeValueStyle.DoubleQuotes);
        private static readonly global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute __tagHelperAttribute_6 = new global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute("asp-area", "", global::Microsoft.AspNetCore.Razor.TagHelpers.HtmlAttributeValueStyle.DoubleQuotes);
        private static readonly global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute __tagHelperAttribute_7 = new global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute("asp-controller", "Home", global::Microsoft.AspNetCore.Razor.TagHelpers.HtmlAttributeValueStyle.DoubleQuotes);
        private static readonly global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute __tagHelperAttribute_8 = new global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute("asp-action", "Index", global::Microsoft.AspNetCore.Razor.TagHelpers.HtmlAttributeValueStyle.DoubleQuotes);
        private static readonly global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute __tagHelperAttribute_9 = new global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute("value", "SqlServer", global::Microsoft.AspNetCore.Razor.TagHelpers.HtmlAttributeValueStyle.DoubleQuotes);
        private static readonly global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute __tagHelperAttribute_10 = new global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute("asp-controller", "Database", global::Microsoft.AspNetCore.Razor.TagHelpers.HtmlAttributeValueStyle.DoubleQuotes);
        private static readonly global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute __tagHelperAttribute_11 = new global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute("asp-action", "Connect", global::Microsoft.AspNetCore.Razor.TagHelpers.HtmlAttributeValueStyle.DoubleQuotes);
        private static readonly global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute __tagHelperAttribute_12 = new global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute("method", "post", global::Microsoft.AspNetCore.Razor.TagHelpers.HtmlAttributeValueStyle.DoubleQuotes);
        private static readonly global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute __tagHelperAttribute_13 = new global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute("id", new global::Microsoft.AspNetCore.Html.HtmlString("dbConnectForm"), global::Microsoft.AspNetCore.Razor.TagHelpers.HtmlAttributeValueStyle.DoubleQuotes);
        private static readonly global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute __tagHelperAttribute_14 = new global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute("src", new global::Microsoft.AspNetCore.Html.HtmlString("~/lib/jquery/dist/jquery.min.js"), global::Microsoft.AspNetCore.Razor.TagHelpers.HtmlAttributeValueStyle.DoubleQuotes);
        private static readonly global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute __tagHelperAttribute_15 = new global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute("src", new global::Microsoft.AspNetCore.Html.HtmlString("~/lib/bootstrap/dist/js/bootstrap.bundle.min.js"), global::Microsoft.AspNetCore.Razor.TagHelpers.HtmlAttributeValueStyle.DoubleQuotes);
        private static readonly global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute __tagHelperAttribute_16 = new global::Microsoft.AspNetCore.Razor.TagHelpers.TagHelperAttribute("src", "~/js/site.js", global::Microsoft.AspNetCore.Razor.TagHelpers.HtmlAttributeValueStyle.DoubleQuotes);
        #line hidden
        #pragma warning disable 0649
        private global::Microsoft.AspNetCore.Razor.Runtime.TagHelpers.TagHelperExecutionContext __tagHelperExecutionContext;
        #pragma warning restore 0649
        private global::Microsoft.AspNetCore.Razor.Runtime.TagHelpers.TagHelperRunner __tagHelperRunner = new global::Microsoft.AspNetCore.Razor.Runtime.TagHelpers.TagHelperRunner();
        #pragma warning disable 0169
        private string __tagHelperStringValueBuffer;
        #pragma warning restore 0169
        private global::Microsoft.AspNetCore.Razor.Runtime.TagHelpers.TagHelperScopeManager __backed__tagHelperScopeManager = null;
        private global::Microsoft.AspNetCore.Razor.Runtime.TagHelpers.TagHelperScopeManager __tagHelperScopeManager
        {
            get
            {
                if (__backed__tagHelperScopeManager == null)
                {
                    __backed__tagHelperScopeManager = new global::Microsoft.AspNetCore.Razor.Runtime.TagHelpers.TagHelperScopeManager(StartTagHelperWritingScope, EndTagHelperWritingScope);
                }
                return __backed__tagHelperScopeManager;
            }
        }
        private global::Microsoft.AspNetCore.Mvc.Razor.TagHelpers.HeadTagHelper __Microsoft_AspNetCore_Mvc_Razor_TagHelpers_HeadTagHelper;
        private global::Microsoft.AspNetCore.Mvc.TagHelpers.ScriptTagHelper __Microsoft_AspNetCore_Mvc_TagHelpers_ScriptTagHelper;
        private global::Microsoft.AspNetCore.Mvc.Razor.TagHelpers.UrlResolutionTagHelper __Microsoft_AspNetCore_Mvc_Razor_TagHelpers_UrlResolutionTagHelper;
        private global::Microsoft.AspNetCore.Mvc.TagHelpers.LinkTagHelper __Microsoft_AspNetCore_Mvc_TagHelpers_LinkTagHelper;
        private global::Microsoft.AspNetCore.Mvc.Razor.TagHelpers.BodyTagHelper __Microsoft_AspNetCore_Mvc_Razor_TagHelpers_BodyTagHelper;
        private global::Microsoft.AspNetCore.Mvc.TagHelpers.AnchorTagHelper __Microsoft_AspNetCore_Mvc_TagHelpers_AnchorTagHelper;
        private global::Microsoft.AspNetCore.Mvc.TagHelpers.FormTagHelper __Microsoft_AspNetCore_Mvc_TagHelpers_FormTagHelper;
        private global::Microsoft.AspNetCore.Mvc.TagHelpers.RenderAtEndOfFormTagHelper __Microsoft_AspNetCore_Mvc_TagHelpers_RenderAtEndOfFormTagHelper;
        private global::Microsoft.AspNetCore.Mvc.TagHelpers.OptionTagHelper __Microsoft_AspNetCore_Mvc_TagHelpers_OptionTagHelper;
        #pragma warning disable 1998
        public async override global::System.Threading.Tasks.Task ExecuteAsync()
        {
            WriteLiteral("<!DOCTYPE html>\r\n<html lang=\"en\">\r\n");
            __tagHelperExecutionContext = __tagHelperScopeManager.Begin("head", global::Microsoft.AspNetCore.Razor.TagHelpers.TagMode.StartTagAndEndTag, "de5807ea14a7b924fdda14116d2dd2fcb3b926490b36b03cbccaa072df8c12dc9794", async() => {
                WriteLiteral("\r\n    <meta charset=\"utf-8\" />\r\n    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\" />\r\n    <title>");
                Write(
#nullable restore
#line (6,13)-(6,30) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\Shared\_Layout.cshtml"
ViewData["Title"]

#line default
#line hidden
#nullable disable
                );
                WriteLiteral(" - StajWebProjesi</title>\r\n    ");
                __tagHelperExecutionContext = __tagHelperScopeManager.Begin("script", global::Microsoft.AspNetCore.Razor.TagHelpers.TagMode.StartTagAndEndTag, "de5807ea14a7b924fdda14116d2dd2fcb3b926490b36b03cbccaa072df8c12dc10504", async() => {
                }
                );
                __Microsoft_AspNetCore_Mvc_TagHelpers_ScriptTagHelper = CreateTagHelper<global::Microsoft.AspNetCore.Mvc.TagHelpers.ScriptTagHelper>();
                __tagHelperExecutionContext.Add(__Microsoft_AspNetCore_Mvc_TagHelpers_ScriptTagHelper);
                __Microsoft_AspNetCore_Mvc_TagHelpers_ScriptTagHelper.Type = (string)__tagHelperAttribute_0.Value;
                __tagHelperExecutionContext.AddTagHelperAttribute(__tagHelperAttribute_0);
                await __tagHelperRunner.RunAsync(__tagHelperExecutionContext);
                if (!__tagHelperExecutionContext.Output.IsContentModified)
                {
                    await __tagHelperExecutionContext.SetOutputContentAsync();
                }
                Write(__tagHelperExecutionContext.Output);
                __tagHelperExecutionContext = __tagHelperScopeManager.End();
                WriteLiteral("\r\n    ");
                __tagHelperExecutionContext = __tagHelperScopeManager.Begin("link", global::Microsoft.AspNetCore.Razor.TagHelpers.TagMode.SelfClosing, "de5807ea14a7b924fdda14116d2dd2fcb3b926490b36b03cbccaa072df8c12dc11710", async() => {
                }
                );
                __Microsoft_AspNetCore_Mvc_Razor_TagHelpers_UrlResolutionTagHelper = CreateTagHelper<global::Microsoft.AspNetCore.Mvc.Razor.TagHelpers.UrlResolutionTagHelper>();
                __tagHelperExecutionContext.Add(__Microsoft_AspNetCore_Mvc_Razor_TagHelpers_UrlResolutionTagHelper);
                __tagHelperExecutionContext.AddHtmlAttribute(__tagHelperAttribute_1);
                __tagHelperExecutionContext.AddHtmlAttribute(__tagHelperAttribute_2);
                await __tagHelperRunner.RunAsync(__tagHelperExecutionContext);
                if (!__tagHelperExecutionContext.Output.IsContentModified)
                {
                    await __tagHelperExecutionContext.SetOutputContentAsync();
                }
                Write(__tagHelperExecutionContext.Output);
                __tagHelperExecutionContext = __tagHelperScopeManager.End();
                WriteLiteral("\r\n    ");
                __tagHelperExecutionContext = __tagHelperScopeManager.Begin("link", global::Microsoft.AspNetCore.Razor.TagHelpers.TagMode.SelfClosing, "de5807ea14a7b924fdda14116d2dd2fcb3b926490b36b03cbccaa072df8c12dc12913", async() => {
                }
                );
                __Microsoft_AspNetCore_Mvc_Razor_TagHelpers_UrlResolutionTagHelper = CreateTagHelper<global::Microsoft.AspNetCore.Mvc.Razor.TagHelpers.UrlResolutionTagHelper>();
                __tagHelperExecutionContext.Add(__Microsoft_AspNetCore_Mvc_Razor_TagHelpers_UrlResolutionTagHelper);
                __Microsoft_AspNetCore_Mvc_TagHelpers_LinkTagHelper = CreateTagHelper<global::Microsoft.AspNetCore.Mvc.TagHelpers.LinkTagHelper>();
                __tagHelperExecutionContext.Add(__Microsoft_AspNetCore_Mvc_TagHelpers_LinkTagHelper);
                __tagHelperExecutionContext.AddHtmlAttribute(__tagHelperAttribute_1);
                __Microsoft_AspNetCore_Mvc_TagHelpers_LinkTagHelper.Href = (string)__tagHelperAttribute_3.Value;
                __tagHelperExecutionContext.AddTagHelperAttribute(__tagHelperAttribute_3);
                __Microsoft_AspNetCore_Mvc_TagHelpers_LinkTagHelper.AppendVersion = 
#nullable restore
#line (9,70)-(9,74) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\Shared\_Layout.cshtml"
true

#line default
#line hidden
#nullable disable
                ;
                __tagHelperExecutionContext.AddTagHelperAttribute("asp-append-version", __Microsoft_AspNetCore_Mvc_TagHelpers_LinkTagHelper.AppendVersion, global::Microsoft.AspNetCore.Razor.TagHelpers.HtmlAttributeValueStyle.DoubleQuotes);
                await __tagHelperRunner.RunAsync(__tagHelperExecutionContext);
                if (!__tagHelperExecutionContext.Output.IsContentModified)
                {
                    await __tagHelperExecutionContext.SetOutputContentAsync();
                }
                Write(__tagHelperExecutionContext.Output);
                __tagHelperExecutionContext = __tagHelperScopeManager.End();
                WriteLiteral("\r\n    ");
                __tagHelperExecutionContext = __tagHelperScopeManager.Begin("link", global::Microsoft.AspNetCore.Razor.TagHelpers.TagMode.SelfClosing, "de5807ea14a7b924fdda14116d2dd2fcb3b926490b36b03cbccaa072df8c12dc15007", async() => {
                }
                );
                __Microsoft_AspNetCore_Mvc_Razor_TagHelpers_UrlResolutionTagHelper = CreateTagHelper<global::Microsoft.AspNetCore.Mvc.Razor.TagHelpers.UrlResolutionTagHelper>();
                __tagHelperExecutionContext.Add(__Microsoft_AspNetCore_Mvc_Razor_TagHelpers_UrlResolutionTagHelper);
                __Microsoft_AspNetCore_Mvc_TagHelpers_LinkTagHelper = CreateTagHelper<global::Microsoft.AspNetCore.Mvc.TagHelpers.LinkTagHelper>();
                __tagHelperExecutionContext.Add(__Microsoft_AspNetCore_Mvc_TagHelpers_LinkTagHelper);
                __tagHelperExecutionContext.AddHtmlAttribute(__tagHelperAttribute_1);
                __Microsoft_AspNetCore_Mvc_TagHelpers_LinkTagHelper.Href = (string)__tagHelperAttribute_4.Value;
                __tagHelperExecutionContext.AddTagHelperAttribute(__tagHelperAttribute_4);
                __Microsoft_AspNetCore_Mvc_TagHelpers_LinkTagHelper.AppendVersion = 
#nullable restore
#line (10,83)-(10,87) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\Shared\_Layout.cshtml"
true

#line default
#line hidden
#nullable disable
                ;
                __tagHelperExecutionContext.AddTagHelperAttribute("asp-append-version", __Microsoft_AspNetCore_Mvc_TagHelpers_LinkTagHelper.AppendVersion, global::Microsoft.AspNetCore.Razor.TagHelpers.HtmlAttributeValueStyle.DoubleQuotes);
                await __tagHelperRunner.RunAsync(__tagHelperExecutionContext);
                if (!__tagHelperExecutionContext.Output.IsContentModified)
                {
                    await __tagHelperExecutionContext.SetOutputContentAsync();
                }
                Write(__tagHelperExecutionContext.Output);
                __tagHelperExecutionContext = __tagHelperScopeManager.End();
                WriteLiteral("\r\n");
            }
            );
            __Microsoft_AspNetCore_Mvc_Razor_TagHelpers_HeadTagHelper = CreateTagHelper<global::Microsoft.AspNetCore.Mvc.Razor.TagHelpers.HeadTagHelper>();
            __tagHelperExecutionContext.Add(__Microsoft_AspNetCore_Mvc_Razor_TagHelpers_HeadTagHelper);
            await __tagHelperRunner.RunAsync(__tagHelperExecutionContext);
            if (!__tagHelperExecutionContext.Output.IsContentModified)
            {
                await __tagHelperExecutionContext.SetOutputContentAsync();
            }
            Write(__tagHelperExecutionContext.Output);
            __tagHelperExecutionContext = __tagHelperScopeManager.End();
            WriteLiteral("\r\n");
            __tagHelperExecutionContext = __tagHelperScopeManager.Begin("body", global::Microsoft.AspNetCore.Razor.TagHelpers.TagMode.StartTagAndEndTag, "de5807ea14a7b924fdda14116d2dd2fcb3b926490b36b03cbccaa072df8c12dc17807", async() => {
                WriteLiteral("\r\n    <header b-ld5ijkdnkk>\r\n        <nav b-ld5ijkdnkk class=\"navbar navbar-expand-sm navbar-toggleable-sm custom-navbar mb-3\">\r\n            <div b-ld5ijkdnkk class=\"container-fluid\">\r\n                ");
                __tagHelperExecutionContext = __tagHelperScopeManager.Begin("a", global::Microsoft.AspNetCore.Razor.TagHelpers.TagMode.StartTagAndEndTag, "de5807ea14a7b924fdda14116d2dd2fcb3b926490b36b03cbccaa072df8c12dc18299", async() => {
                    WriteLiteral("StajWebProjesi");
                }
                );
                __Microsoft_AspNetCore_Mvc_TagHelpers_AnchorTagHelper = CreateTagHelper<global::Microsoft.AspNetCore.Mvc.TagHelpers.AnchorTagHelper>();
                __tagHelperExecutionContext.Add(__Microsoft_AspNetCore_Mvc_TagHelpers_AnchorTagHelper);
                __tagHelperExecutionContext.AddHtmlAttribute(__tagHelperAttribute_5);
                __Microsoft_AspNetCore_Mvc_TagHelpers_AnchorTagHelper.Area = (string)__tagHelperAttribute_6.Value;
                __tagHelperExecutionContext.AddTagHelperAttribute(__tagHelperAttribute_6);
                __Microsoft_AspNetCore_Mvc_TagHelpers_AnchorTagHelper.Controller = (string)__tagHelperAttribute_7.Value;
                __tagHelperExecutionContext.AddTagHelperAttribute(__tagHelperAttribute_7);
                __Microsoft_AspNetCore_Mvc_TagHelpers_AnchorTagHelper.Action = (string)__tagHelperAttribute_8.Value;
                __tagHelperExecutionContext.AddTagHelperAttribute(__tagHelperAttribute_8);
                await __tagHelperRunner.RunAsync(__tagHelperExecutionContext);
                if (!__tagHelperExecutionContext.Output.IsContentModified)
                {
                    await __tagHelperExecutionContext.SetOutputContentAsync();
                }
                Write(__tagHelperExecutionContext.Output);
                __tagHelperExecutionContext = __tagHelperScopeManager.End();
                WriteLiteral(@"
                <button b-ld5ijkdnkk class=""navbar-toggler"" type=""button"" data-bs-toggle=""collapse"" data-bs-target="".navbar-collapse"" aria-controls=""navbarSupportedContent""
                        aria-expanded=""false"" aria-label=""Toggle navigation"">
                    <span b-ld5ijkdnkk class=""navbar-toggler-icon""></span>
                </button>
                <div b-ld5ijkdnkk class=""navbar-collapse collapse d-sm-inline-flex justify-content-between"">
                    <ul b-ld5ijkdnkk class=""navbar-nav"">
                        <li b-ld5ijkdnkk class=""nav-item d-flex align-items-center"">
                            <div b-ld5ijkdnkk class=""toolbar-group"">
                                <button b-ld5ijkdnkk class=""toolbar-btn toolbar-db"" data-bs-toggle=""modal"" data-bs-target=""#dbConnectModal"">Veritabanına Bağlan</button>
                                <button b-ld5ijkdnkk id=""dbDisconnectBtn"" class=""toolbar-btn toolbar-db"" style=""display:none; background:#e74c3c !important;"">Bağlantıyı Kes</bu");
                WriteLiteral(@"tton>
                                <span b-ld5ijkdnkk id=""dbNameDisplay"" class=""toolbar-btn"" style=""background: #2ecc71; color: #fff; border-radius: 4px; padding: 4px 12px; font-size: 12px; display: none;"">Bağlı değil</span>
                            </div>
                        </li>
                    </ul>
                    <div b-ld5ijkdnkk class=""d-flex align-items-center ms-auto"">
                        <button b-ld5ijkdnkk id=""pdfSaveBtn"" class=""toolbar-btn toolbar-db"">PDF olarak kaydet</button>
                        <button b-ld5ijkdnkk id=""btnLogout"" class=""toolbar-btn toolbar-db"" style=""background:#e74c3c !important;"">Çıkış Yap</button>
                    </div>
                </div>
            </div>
        </nav>
    </header>
    <div b-ld5ijkdnkk class=""container"">
        <main b-ld5ijkdnkk role=""main"" class=""pb-3"">
            ");
                Write(
#nullable restore
#line (41,14)-(41,26) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\Shared\_Layout.cshtml"
RenderBody()

#line default
#line hidden
#nullable disable
                );
                WriteLiteral(@"
        </main>
    </div>

    <footer b-ld5ijkdnkk class=""custom-footer"">
        <div b-ld5ijkdnkk class=""container"">
            &copy; 2026 - StajWebProjesi Ömer Faruk Biltekin
        </div>
    </footer>
    <!-- Database Connect Modal -->
    <div b-ld5ijkdnkk class=""modal fade"" id=""dbConnectModal"" tabindex=""-1"" aria-labelledby=""dbConnectModalLabel"" aria-hidden=""true"">
      <div b-ld5ijkdnkk class=""modal-dialog modal-lg"">
        <div b-ld5ijkdnkk class=""modal-content"">
          <div b-ld5ijkdnkk class=""modal-header"">
            <h5 b-ld5ijkdnkk class=""modal-title"" id=""dbConnectModalLabel"">Veritabanına Bağlan</h5>
            <button b-ld5ijkdnkk type=""button"" class=""btn-close"" data-bs-dismiss=""modal"" aria-label=""Close""></button>
          </div>
          <div b-ld5ijkdnkk class=""modal-body"">
            ");
                __tagHelperExecutionContext = __tagHelperScopeManager.Begin("form", global::Microsoft.AspNetCore.Razor.TagHelpers.TagMode.StartTagAndEndTag, "de5807ea14a7b924fdda14116d2dd2fcb3b926490b36b03cbccaa072df8c12dc23200", async() => {
                    WriteLiteral(@"
                <div b-ld5ijkdnkk class=""mb-3"">
                    <label b-ld5ijkdnkk for=""modalProviderSelect"">Provider</label>
                    <select b-ld5ijkdnkk name=""Provider"" class=""form-select"" id=""modalProviderSelect"">
                        
                        ");
                    __tagHelperExecutionContext = __tagHelperScopeManager.Begin("option", global::Microsoft.AspNetCore.Razor.TagHelpers.TagMode.StartTagAndEndTag, "de5807ea14a7b924fdda14116d2dd2fcb3b926490b36b03cbccaa072df8c12dc23784", async() => {
                        WriteLiteral("SqlServer");
                    }
                    );
                    __Microsoft_AspNetCore_Mvc_TagHelpers_OptionTagHelper = CreateTagHelper<global::Microsoft.AspNetCore.Mvc.TagHelpers.OptionTagHelper>();
                    __tagHelperExecutionContext.Add(__Microsoft_AspNetCore_Mvc_TagHelpers_OptionTagHelper);
                    __Microsoft_AspNetCore_Mvc_TagHelpers_OptionTagHelper.Value = (string)__tagHelperAttribute_9.Value;
                    __tagHelperExecutionContext.AddTagHelperAttribute(__tagHelperAttribute_9);
                    await __tagHelperRunner.RunAsync(__tagHelperExecutionContext);
                    if (!__tagHelperExecutionContext.Output.IsContentModified)
                    {
                        await __tagHelperExecutionContext.SetOutputContentAsync();
                    }
                    Write(__tagHelperExecutionContext.Output);
                    __tagHelperExecutionContext = __tagHelperScopeManager.End();
                    WriteLiteral(@"
                    </select>
                </div>

                <div b-ld5ijkdnkk id=""modalSqlServerFields"" style=""display:none;"">
                    <div b-ld5ijkdnkk class=""mb-3"">
                        <label b-ld5ijkdnkk for=""modalServer"">Server Name</label>
                        <input b-ld5ijkdnkk name=""Server"" class=""form-control"" id=""modalServer"" placeholder=""(localdb)\\mssqllocaldb"" />
                    </div>
                    <div b-ld5ijkdnkk class=""mb-3"">
                        <label b-ld5ijkdnkk for=""modalDatabase"">Database Name</label>
                        <input b-ld5ijkdnkk name=""Database"" class=""form-control"" id=""modalDatabase"" />
                    </div>
                    <div b-ld5ijkdnkk id=""modalSqlCreds"" style=""display:none;"">
                        <div b-ld5ijkdnkk class=""mb-3"">
                            <label b-ld5ijkdnkk for=""modalUsername"">Username</label>
                            <input b-ld5ijkdnkk name=""Username"" class=""form-control"" id=""mo");
                    WriteLiteral(@"dalUsername"" />
                        </div>
                        <div b-ld5ijkdnkk class=""mb-3"">
                            <label b-ld5ijkdnkk for=""modalPassword"">Password</label>
                            <input b-ld5ijkdnkk name=""Password"" type=""password"" class=""form-control"" id=""modalPassword"" />
                        </div>
                    </div>
                    <div b-ld5ijkdnkk class=""mb-3"">
                        <label b-ld5ijkdnkk for=""modalConnectionString"">Connection String (optional - overrides other fields)</label>
                        <input b-ld5ijkdnkk name=""ConnectionString"" class=""form-control"" id=""modalConnectionString"" />
                    </div>
                </div>
            ");
                }
                );
                __Microsoft_AspNetCore_Mvc_TagHelpers_FormTagHelper = CreateTagHelper<global::Microsoft.AspNetCore.Mvc.TagHelpers.FormTagHelper>();
                __tagHelperExecutionContext.Add(__Microsoft_AspNetCore_Mvc_TagHelpers_FormTagHelper);
                __Microsoft_AspNetCore_Mvc_TagHelpers_RenderAtEndOfFormTagHelper = CreateTagHelper<global::Microsoft.AspNetCore.Mvc.TagHelpers.RenderAtEndOfFormTagHelper>();
                __tagHelperExecutionContext.Add(__Microsoft_AspNetCore_Mvc_TagHelpers_RenderAtEndOfFormTagHelper);
                __Microsoft_AspNetCore_Mvc_TagHelpers_FormTagHelper.Controller = (string)__tagHelperAttribute_10.Value;
                __tagHelperExecutionContext.AddTagHelperAttribute(__tagHelperAttribute_10);
                __Microsoft_AspNetCore_Mvc_TagHelpers_FormTagHelper.Action = (string)__tagHelperAttribute_11.Value;
                __tagHelperExecutionContext.AddTagHelperAttribute(__tagHelperAttribute_11);
                __Microsoft_AspNetCore_Mvc_TagHelpers_FormTagHelper.Method = (string)__tagHelperAttribute_12.Value;
                __tagHelperExecutionContext.AddTagHelperAttribute(__tagHelperAttribute_12);
                __tagHelperExecutionContext.AddHtmlAttribute(__tagHelperAttribute_13);
                await __tagHelperRunner.RunAsync(__tagHelperExecutionContext);
                if (!__tagHelperExecutionContext.Output.IsContentModified)
                {
                    await __tagHelperExecutionContext.SetOutputContentAsync();
                }
                Write(__tagHelperExecutionContext.Output);
                __tagHelperExecutionContext = __tagHelperScopeManager.End();
                WriteLiteral(@"
          </div>
          <div b-ld5ijkdnkk class=""modal-footer"">
            <button b-ld5ijkdnkk type=""button"" class=""btn btn-secondary"" data-bs-dismiss=""modal"">Kapat</button>
            <button b-ld5ijkdnkk type=""submit"" form=""dbConnectForm"" class=""btn btn-primary"" id=""dbConnectBtn"">Bağlan</button>
          </div>
        </div>
      </div>
    </div>

    ");
                __tagHelperExecutionContext = __tagHelperScopeManager.Begin("script", global::Microsoft.AspNetCore.Razor.TagHelpers.TagMode.StartTagAndEndTag, "de5807ea14a7b924fdda14116d2dd2fcb3b926490b36b03cbccaa072df8c12dc29104", async() => {
                }
                );
                __Microsoft_AspNetCore_Mvc_Razor_TagHelpers_UrlResolutionTagHelper = CreateTagHelper<global::Microsoft.AspNetCore.Mvc.Razor.TagHelpers.UrlResolutionTagHelper>();
                __tagHelperExecutionContext.Add(__Microsoft_AspNetCore_Mvc_Razor_TagHelpers_UrlResolutionTagHelper);
                __tagHelperExecutionContext.AddHtmlAttribute(__tagHelperAttribute_14);
                await __tagHelperRunner.RunAsync(__tagHelperExecutionContext);
                if (!__tagHelperExecutionContext.Output.IsContentModified)
                {
                    await __tagHelperExecutionContext.SetOutputContentAsync();
                }
                Write(__tagHelperExecutionContext.Output);
                __tagHelperExecutionContext = __tagHelperScopeManager.End();
                WriteLiteral("\r\n    ");
                __tagHelperExecutionContext = __tagHelperScopeManager.Begin("script", global::Microsoft.AspNetCore.Razor.TagHelpers.TagMode.StartTagAndEndTag, "de5807ea14a7b924fdda14116d2dd2fcb3b926490b36b03cbccaa072df8c12dc30229", async() => {
                }
                );
                __Microsoft_AspNetCore_Mvc_Razor_TagHelpers_UrlResolutionTagHelper = CreateTagHelper<global::Microsoft.AspNetCore.Mvc.Razor.TagHelpers.UrlResolutionTagHelper>();
                __tagHelperExecutionContext.Add(__Microsoft_AspNetCore_Mvc_Razor_TagHelpers_UrlResolutionTagHelper);
                __tagHelperExecutionContext.AddHtmlAttribute(__tagHelperAttribute_15);
                await __tagHelperRunner.RunAsync(__tagHelperExecutionContext);
                if (!__tagHelperExecutionContext.Output.IsContentModified)
                {
                    await __tagHelperExecutionContext.SetOutputContentAsync();
                }
                Write(__tagHelperExecutionContext.Output);
                __tagHelperExecutionContext = __tagHelperScopeManager.End();
                WriteLiteral("\r\n    ");
                __tagHelperExecutionContext = __tagHelperScopeManager.Begin("script", global::Microsoft.AspNetCore.Razor.TagHelpers.TagMode.StartTagAndEndTag, "de5807ea14a7b924fdda14116d2dd2fcb3b926490b36b03cbccaa072df8c12dc31354", async() => {
                }
                );
                __Microsoft_AspNetCore_Mvc_Razor_TagHelpers_UrlResolutionTagHelper = CreateTagHelper<global::Microsoft.AspNetCore.Mvc.Razor.TagHelpers.UrlResolutionTagHelper>();
                __tagHelperExecutionContext.Add(__Microsoft_AspNetCore_Mvc_Razor_TagHelpers_UrlResolutionTagHelper);
                __Microsoft_AspNetCore_Mvc_TagHelpers_ScriptTagHelper = CreateTagHelper<global::Microsoft.AspNetCore.Mvc.TagHelpers.ScriptTagHelper>();
                __tagHelperExecutionContext.Add(__Microsoft_AspNetCore_Mvc_TagHelpers_ScriptTagHelper);
                __Microsoft_AspNetCore_Mvc_TagHelpers_ScriptTagHelper.Src = (string)__tagHelperAttribute_16.Value;
                __tagHelperExecutionContext.AddTagHelperAttribute(__tagHelperAttribute_16);
                __Microsoft_AspNetCore_Mvc_TagHelpers_ScriptTagHelper.AppendVersion = 
#nullable restore
#line (104,52)-(104,56) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\Shared\_Layout.cshtml"
true

#line default
#line hidden
#nullable disable
                ;
                __tagHelperExecutionContext.AddTagHelperAttribute("asp-append-version", __Microsoft_AspNetCore_Mvc_TagHelpers_ScriptTagHelper.AppendVersion, global::Microsoft.AspNetCore.Razor.TagHelpers.HtmlAttributeValueStyle.DoubleQuotes);
                await __tagHelperRunner.RunAsync(__tagHelperExecutionContext);
                if (!__tagHelperExecutionContext.Output.IsContentModified)
                {
                    await __tagHelperExecutionContext.SetOutputContentAsync();
                }
                Write(__tagHelperExecutionContext.Output);
                __tagHelperExecutionContext = __tagHelperScopeManager.End();
                WriteLiteral(@"
    <script>
        (function(){
            const provider = document.getElementById('modalProviderSelect');
            const sqlServerFields = document.getElementById('modalSqlServerFields');
            const authSelect = document.getElementById('modalAuthSelect');
            const sqlCreds = document.getElementById('modalSqlCreds');

            function updateFields(){
                if(!provider) return;
                if(provider.value === 'SqlServer'){
                    sqlServerFields.style.display = '';
                    updateAuth();
                } else {
                    sqlServerFields.style.display = 'none';
                }
            }
            function updateAuth(){
                if(!authSelect) return;
                if(authSelect.value === 'SqlServer') sqlCreds.style.display=''; else sqlCreds.style.display='none';
            }
            if(provider) provider.addEventListener('change', updateFields);
            if(authSelect) authSelect.addEv");
                WriteLiteral(@"entListener('change', updateAuth);
            // initialize when modal shown
            var dbModal = document.getElementById('dbConnectModal');
            if(dbModal){
                dbModal.addEventListener('shown.bs.modal', function(){ updateFields(); });
            }
        })();

        // F5'te veritabanı adını restore et
        (function(){
            const dbNameDisplay = document.getElementById('dbNameDisplay');
            if (!dbNameDisplay) return;
            fetch('/Database/GetConnectionStatus', { method: 'GET', headers: { 'Accept': 'application/json' } })
                .then(r => {
                    if (!r.ok) throw new Error('HTTP ' + r.status);
                    return r.json();
                })
                .then(data => {
                    if (data.connected) {
                        dbNameDisplay.style.display = 'inline-block';
                        dbNameDisplay.textContent = 'Bağlı: ' + (data.database || 'Bilinmeyen');
                        // F5 sonrası");
                WriteLiteral(@" otomatik yükleme
                        document.dispatchEvent(new CustomEvent('dbConnected'));
                    }
                })
                .catch(err => console.warn('DB status check failed:', err));
        })();

        
        document.getElementById('dbConnectForm').addEventListener('submit', function(e){
            e.preventDefault();
            
            const formData = new FormData(this);
            
            fetch('/Database/Connect', {
                method: 'POST',
                headers: { 'Accept': 'application/json' },
                body: formData
            })
            .then(response => {
                if (!response.ok) throw new Error('HTTP ' + response.status);
                return response.json();
            })
            .then(data => {
                if(data.success){
                    const connectModal = bootstrap.Modal.getInstance(document.getElementById('dbConnectModal'));
                    if (connectModal) connectModal.hide();

          ");
                WriteLiteral(@"          const dbNameDisplay = document.getElementById('dbNameDisplay');
                    if (dbNameDisplay) {
                        dbNameDisplay.style.display = 'inline-block';
                        dbNameDisplay.textContent = 'Bağlı: ' + (data.database || 'Bilinmeyen');
                    }

                    // Otomatik yüklemesi için global event dispatch
                    document.dispatchEvent(new CustomEvent('dbConnected'));
                } else {
                    alert('Hata: ' + (data.error || 'Bilinmeyen hata'));
                }
            })
            .catch(error => {
                console.error('Connection error:', error);
                alert('Bağlantı hatası: ' + error.message);
            });
        });

        // Bağlantıyı Kes butonu
        (function(){
            const disconnectBtn = document.getElementById('dbDisconnectBtn');
            if(disconnectBtn){
                disconnectBtn.addEventListener('click', function(){
                    fetch('/Databa");
                WriteLiteral(@"se/Disconnect', { method: 'POST', headers: { 'Accept': 'application/json' } })
                    .then(r => {
                        if (!r.ok) throw new Error('HTTP ' + r.status);
                        return r.json();
                    })
                    .then(data => {
                        const dbNameDisplay = document.getElementById('dbNameDisplay');
                        if (dbNameDisplay) {
                            dbNameDisplay.style.display = 'none';
                            dbNameDisplay.textContent = 'Bağlı değil';
                        }
                        disconnectBtn.style.display = 'none';
                    })
                    .catch(err => console.warn('Disconnect error:', err));
                });
            }
        })();

        // Çıkış Yap butonu
        (function(){
            const logoutBtn = document.getElementById('btnLogout');
            if(logoutBtn){
                logoutBtn.addEventListener('click', function(){
                    fetch('");
                WriteLiteral(@"/Account/Logout', { method: 'POST', headers: { 'Accept': 'application/json' } })
                    .then(r => {
                        if (!r.ok) throw new Error('HTTP ' + r.status);
                        return r.json();
                    })
                    .then(data => {
                        window.location.href = '/Account/Login';
                    })
                    .catch(err => {
                        console.warn('Logout error:', err);
                        window.location.href = '/Account/Login';
                    });
                });
            }
        })();

        // Bağlı ise disconnect butonunu göster
        (function(){
            const disconnectBtn = document.getElementById('dbDisconnectBtn');
            const dbNameDisplay = document.getElementById('dbNameDisplay');
            if (!disconnectBtn || !dbNameDisplay) return;
            fetch('/Database/GetConnectionStatus', { method: 'GET', headers: { 'Accept': 'application/json' } })
                .then(");
                WriteLiteral(@"r => {
                    if (!r.ok) throw new Error('HTTP ' + r.status);
                    return r.json();
                })
                .then(data => {
                    if (data.connected) {
                        dbNameDisplay.style.display = 'inline-block';
                        dbNameDisplay.textContent = 'Bağlı: ' + (data.database || 'Bilinmeyen');
                        disconnectBtn.style.display = 'inline-block';
                    }
                })
                .catch(err => console.warn('DB status check failed:', err));
        })();

    </script>
    ");
                Write(
#nullable restore
#line (257,6)-(257,58) "C:\Users\omer\Desktop\staj proje\StajWebProjesi\Views\Shared\_Layout.cshtml"
await RenderSectionAsync("Scripts", required: false)

#line default
#line hidden
#nullable disable
                );
                WriteLiteral("\r\n");
            }
            );
            __Microsoft_AspNetCore_Mvc_Razor_TagHelpers_BodyTagHelper = CreateTagHelper<global::Microsoft.AspNetCore.Mvc.Razor.TagHelpers.BodyTagHelper>();
            __tagHelperExecutionContext.Add(__Microsoft_AspNetCore_Mvc_Razor_TagHelpers_BodyTagHelper);
            await __tagHelperRunner.RunAsync(__tagHelperExecutionContext);
            if (!__tagHelperExecutionContext.Output.IsContentModified)
            {
                await __tagHelperExecutionContext.SetOutputContentAsync();
            }
            Write(__tagHelperExecutionContext.Output);
            __tagHelperExecutionContext = __tagHelperScopeManager.End();
            WriteLiteral("\r\n</html>\r\n");
        }
        #pragma warning restore 1998
        #nullable restore
        [global::Microsoft.AspNetCore.Mvc.Razor.Internal.RazorInjectAttribute]
        public global::Microsoft.AspNetCore.Mvc.ViewFeatures.IModelExpressionProvider ModelExpressionProvider { get; private set; } = default!;
        #nullable disable
        #nullable restore
        [global::Microsoft.AspNetCore.Mvc.Razor.Internal.RazorInjectAttribute]
        public global::Microsoft.AspNetCore.Mvc.IUrlHelper Url { get; private set; } = default!;
        #nullable disable
        #nullable restore
        [global::Microsoft.AspNetCore.Mvc.Razor.Internal.RazorInjectAttribute]
        public global::Microsoft.AspNetCore.Mvc.IViewComponentHelper Component { get; private set; } = default!;
        #nullable disable
        #nullable restore
        [global::Microsoft.AspNetCore.Mvc.Razor.Internal.RazorInjectAttribute]
        public global::Microsoft.AspNetCore.Mvc.Rendering.IJsonHelper Json { get; private set; } = default!;
        #nullable disable
        #nullable restore
        [global::Microsoft.AspNetCore.Mvc.Razor.Internal.RazorInjectAttribute]
        public global::Microsoft.AspNetCore.Mvc.Rendering.IHtmlHelper<dynamic> Html { get; private set; } = default!;
        #nullable disable
    }
}
#pragma warning restore 1591
ParseOptions.0.json