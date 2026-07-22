using Microsoft.AspNetCore.Mvc;
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
