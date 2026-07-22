using System.ComponentModel.DataAnnotations;

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
