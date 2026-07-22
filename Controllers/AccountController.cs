using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.Sqlite;
using System.Security.Cryptography;
using System.Text;
using System.IO;

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
            var dir = new DirectoryInfo(baseDir);
            while (dir.Parent != null && !File.Exists(Path.Combine(dir.FullName, "stajweb.db")))
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
