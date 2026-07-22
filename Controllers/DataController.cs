using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using StajWebProjesi.Models;

namespace StajWebProjesi.Controllers;

using Microsoft.AspNetCore.Mvc; 
using Microsoft.AspNetCore.Authorization;
using Microsoft.Data.SqlClient;

//[Authorize] // Bunu ekle
[ApiController]
[Route("[controller]")]
public class DataController : ControllerBase

{
    private readonly IConfiguration _configuration;

    public DataController(IConfiguration configuration)
    {
        _configuration = configuration;
    }

    private string GetConnectionString()
    {
        // Önce doğrudan kaydedilen connection string'i dene
        var connStr = HttpContext.Session.GetString("DbConnectionString");
        if (!string.IsNullOrEmpty(connStr))
        {
            return connStr;
        }
        
        // Fallback: JSON'dan deserialize et
        var conn = HttpContext.Session.GetString("DbConnectionInfo");
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
            var connectionString = GetConnectionString();
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
            var connectionString = GetConnectionString();
            using var conn = new SqlConnection(connectionString);
            await conn.OpenAsync();

            // Timestamp kolonunu otomatik bul
            string tsCol = "Timestamp";
            string findTsSql = @"SELECT TOP 1 COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS 
                                 WHERE TABLE_NAME = 'HIST_TREND' 
                                 AND DATA_TYPE IN ('datetime','datetime2','date','smalldatetime')
                                 ORDER BY ORDINAL_POSITION";
            using (var cmdTs = new SqlCommand(findTsSql, conn))
            {
                var tsResult = await cmdTs.ExecuteScalarAsync();
                if (tsResult != null) tsCol = tsResult.ToString()!;
            }

            // HIST_TREND tablosunda BATCH_ID kolonunun adını bul (BATCH_ID veya BATCHID olabilir)
            string batchCol = "BATCH_ID";
            string findBatchSql = @"SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS 
                                    WHERE TABLE_NAME = 'HIST_TREND' 
                                    AND COLUMN_NAME LIKE '%BATCH%'";
            using (var cmdB = new SqlCommand(findBatchSql, conn))
            {
                var batchResult = await cmdB.ExecuteScalarAsync();
                if (batchResult != null) batchCol = batchResult.ToString()!;
            }

            // Tabloda gerçekten var olan kolonları bul (olmayanları atla)
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

            // Timestamp kolonunu ekle
            existingCols.Add(tsCol);
            existingCols.Add(batchCol);

            var validCols = requestedCols.Where(c => existingCols.Contains(c)).ToList();
            var colList = validCols.Select(c => $"[{c}]").ToList();
            var selectCols = string.Join(", ", colList);

            // Batch'in EN SONU tarihini bul (en yeni veriden geriye doğru)
            string batchDateSql = $"SELECT MAX([{tsCol}]) FROM dbo.HIST_TREND WHERE [{batchCol}] = @batchId";
            DateTime? batchEndDate = null;
            using (var cmdBatch = new SqlCommand(batchDateSql, conn))
            {
                cmdBatch.Parameters.AddWithValue("@batchId", batchId);
                var tsResult = await cmdBatch.ExecuteScalarAsync();
                if (tsResult != null && tsResult != DBNull.Value)
                    batchEndDate = (DateTime)tsResult;
            }

            // Zaman aralığı filtresi - en son tarihten geriye doğru
            string timeFilter = "";
            if (batchEndDate.HasValue)
            {
                // daily: yearCount × 1 gün geriye, monthly: yearCount × 1 ay geriye, yearly: yearCount × 1 yıl geriye
                if (timeRange == "daily")
                    timeFilter = $" AND [{tsCol}] >= DATEADD(day, -{yearCount}, @batchEnd) AND [{tsCol}] <= @batchEnd";
                else if (timeRange == "monthly")
                    timeFilter = $" AND [{tsCol}] >= DATEADD(month, -{yearCount}, @batchEnd) AND [{tsCol}] <= @batchEnd";
                else if (timeRange == "yearly")
                    timeFilter = $" AND [{tsCol}] >= DATEADD(year, -{yearCount}, @batchEnd) AND [{tsCol}] <= @batchEnd";
            }

            // DESC sıralama: en yeni veri en başta
            var sql = $"SELECT [{tsCol}], {selectCols} FROM dbo.HIST_TREND WHERE [{batchCol}] = @batchId{timeFilter} ORDER BY [{tsCol}] DESC";
            
            using var cmd = new SqlCommand(sql, conn);
            cmd.Parameters.AddWithValue("@batchId", batchId);
            if (batchEndDate.HasValue)
                cmd.Parameters.AddWithValue("@batchEnd", batchEndDate.Value);

            using var reader = await cmd.ExecuteReaderAsync();
            var labels = new List<string>();
            var seriesData = new Dictionary<string, List<double>>();
            
            // Tüm istenen kolonları başlat
            foreach (var col in requestedCols)
            {
                seriesData[col] = new List<double>();
            }

            // Tüm kayıtları çek
            var allLabels = new List<string>();
            var allSeries = new Dictionary<string, List<double>>();
            foreach (var col in requestedCols)
                allSeries[col] = new List<double>();
            
            while (await reader.ReadAsync())
            {
                var dt = reader.GetDateTime(0);
                // Tüm modlarda tarih yazmalı (gün/ay/yıl saat)
                string label = dt.ToString("dd.MM.yyyy HH:mm");
                allLabels.Add(label);
                for (int i = 0; i < colList.Count; i++)
                {
                    var colName = validCols[i];
                    var val = reader.IsDBNull(i + 1) ? double.NaN : Convert.ToDouble(reader.GetValue(i + 1));
                    allSeries[colName].Add(val);
                }
            }

            // Çok fazla veri varsa grafik için seyrelt (sampling)
            const int maxPoints = 500;
            if (allLabels.Count > maxPoints)
            {
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

            return Ok(new { labels, series = seriesData, meta = new { timeRange, yearCount, totalRecords = allLabels.Count, batchEnd = batchEndDate?.ToString("yyyy-MM-dd HH:mm:ss") ?? "null" } });
        }
        catch (Exception ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }

    [HttpGet("GetBatchComparison")]
    public async Task<IActionResult> GetBatchComparison([FromQuery] int batchId)
    {
        try
        {
            var connectionString = GetConnectionString();

            // Her sorgu için ayrı bağlantı açarak DataReader çakışmasını önle
            
            // 1. BATCH_MASTER kolonlarını keşfet
            List<string> bmCols;
            using (var conn1 = new SqlConnection(connectionString))
            {
                await conn1.OpenAsync();
                var cmd = new SqlCommand("SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'BATCH_MASTER' AND (COLUMN_NAME LIKE '%KONSIMENTO%' OR COLUMN_NAME LIKE '%CONSENT%')", conn1);
                using var reader = await cmd.ExecuteReaderAsync();
                bmCols = new List<string>();
                while (await reader.ReadAsync()) bmCols.Add(reader.GetString(0));
            }

            // 2. HIST_TREND kolonlarını keşfet
            List<string> htCols;
            using (var conn2 = new SqlConnection(connectionString))
            {
                await conn2.OpenAsync();
                var cmd = new SqlCommand("SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'HIST_TREND'", conn2);
                using var reader = await cmd.ExecuteReaderAsync();
                htCols = new List<string>();
                while (await reader.ReadAsync()) htCols.Add(reader.GetString(0));
            }

            // 3. Batch ID kolonunu keşfet
            string batchCol = "BATCH_ID";
            using (var conn3 = new SqlConnection(connectionString))
            {
                await conn3.OpenAsync();
                var cmd = new SqlCommand("SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'HIST_TREND' AND COLUMN_NAME LIKE '%BATCH%'", conn3);
                using var reader = await cmd.ExecuteReaderAsync();
                if (await reader.ReadAsync())
                    batchCol = reader.GetString(0);
            }

            // 4. Kolon isimlerini belirle
            string konsVolCol = bmCols.FirstOrDefault(c => c.Contains("VOLUME")) ?? bmCols.FirstOrDefault(c => c.Contains("GSV")) ?? "KONSIMENTO_VOLUME";
            string konsMassCol = bmCols.FirstOrDefault(c => c.Contains("MASS") || c.Contains("WEIGHT")) ?? "KONSIMENTO_MASS";
            string gsColName = htCols.FirstOrDefault(c => c == "GS") ?? htCols.FirstOrDefault() ?? "GS";
            string massColName = htCols.Count > 1 ? htCols.LastOrDefault(c => c == "MASS") ?? htCols.Last() : htCols.FirstOrDefault(c => c != gsColName) ?? "MASS";

            // 5. Tek sorgu ile tüm değerleri al (ayrı bağlantı)
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
                    string gsvKons = reader.IsDBNull(0) ? "0" : reader.GetValue(0).ToString();
                    string massKons = reader.IsDBNull(1) ? "0" : reader.GetValue(1).ToString();
                    string gsvMeter = reader.IsDBNull(2) ? "0" : reader.GetValue(2).ToString();
                    string massMeter = reader.IsDBNull(3) ? "0" : reader.GetValue(3).ToString();

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

    [HttpGet("SelectedTables")]
    public IActionResult SelectedTables()
    {
        try
        {
            var json = HttpContext.Session.GetString("SelectedTables");
            if (string.IsNullOrEmpty(json)) return Ok(new { selected = new string[0] });
            var arr = JsonSerializer.Deserialize<string[]>(json) ?? Array.Empty<string>();
            return Ok(new { selected = arr });
        }
        catch { return Ok(new { selected = new string[0] }); }
    }
    
    [HttpPost("Connect")]
    public IActionResult Connect([FromBody] DbConnectionInfo info)
    {
        if (string.IsNullOrEmpty(info.ConnectionString)) 
        {
            info.ConnectionString = $"Server={info.Server};Database={info.Database};Trusted_Connection=True;TrustServerCertificate=True;";
        }
        
        HttpContext.Session.SetString("DbConnectionInfo", JsonSerializer.Serialize(info));
        return Ok();
    }

    [HttpGet("TableColumns")]
    public async Task<IActionResult> TableColumns(string table)
    {
        var connJson = HttpContext.Session.GetString("DbConnectionInfo");
        if (string.IsNullOrEmpty(connJson)) return BadRequest(new { error = "No DB connection in session" });
        
        var info = JsonSerializer.Deserialize<DbConnectionInfo>(connJson);

        var cols = await GetColumnsForTableAsync(table, info!);
        if (cols == null) return BadRequest(new { error = "Could not read table columns" });

        var autoMapping = new ColumnMappingDto
        {
            TimestampColumn = cols.FirstOrDefault(c => c.Contains("DATE", StringComparison.OrdinalIgnoreCase) || c.Contains("TIME", StringComparison.OrdinalIgnoreCase)) ?? "Timestamp",
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
        
        string tableName = table.Contains(".") ? table.Split('.').Last() : table;
        
        // try-catch bloğunu tamamen kaldır veya içeriğini değiştir
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
        public string TimestampColumn { get; set; } = "Timestamp";
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
        var connJson = HttpContext.Session.GetString("DbConnectionInfo");
        if (string.IsNullOrEmpty(connJson)) return BadRequest(new { error = "Session'da bağlantı bilgisi bulunamadı." });
        
        var info = JsonSerializer.Deserialize<DbConnectionInfo>(connJson);

        if (info == null || string.IsNullOrWhiteSpace(info.ConnectionString))
        {
            return BadRequest(new { error = "ConnectionString null geldi! Bağlantı modalından verileri kaydettiğinden emin ol." });
        }

        string connStr = info.ConnectionString;
        var table = req.Table ?? HttpContext.Session.GetString("SelectedTables")?.Trim('[', ']', '"') ?? "HIST_TREND";
        var tsColRaw = req.TimestampColumn ?? "Timestamp";
        var tsCol = tsColRaw;
        var colsList = req.Columns;

        try
        {
            using var conn = new SqlConnection(connStr);
            await conn.OpenAsync();

            var colsEscaped = req.Columns.Select(c => "[" + c + "]").ToArray();
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

    private static string EscapeIdentifier(string name) => name;
}
