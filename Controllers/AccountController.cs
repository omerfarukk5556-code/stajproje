using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.Sqlite;
using StajWebProjesi.Models;

namespace StajWebProjesi.Controllers
{
    [AllowAnonymous]
    public class AccountController : Controller
    {
        private string GetConnectionString()
        {
            // Projenin tam yolunu yaz (Hata payını sıfırla)
            string dbPath = @"C:\Users\omer\Desktop\staj proje\StajWebProjesi\stajweb.db";
            return $"Data Source={dbPath}";
        }
        
        [HttpGet]
        public IActionResult Login() => View();

        [HttpPost]
        public IActionResult Login(string Username, string Password, string actionType) 
        {
            var connString = GetConnectionString();
            using var conn = new SqliteConnection(connString);
            conn.Open();

            // BLOĞU METODUN İÇİNE ALDIK
            if (actionType == "register")
            {
                // 1. Tablo yoksa oluştur
                var createTableCmd = new SqliteCommand(@"CREATE TABLE IF NOT EXISTS Users (
                                                    Id INTEGER PRIMARY KEY AUTOINCREMENT, 
                                                    Username TEXT NOT NULL, 
                                                    Password TEXT NOT NULL)", conn);
                createTableCmd.ExecuteNonQuery();

                // 2. Kullanıcıyı ekle
                var insertCmd = new SqliteCommand("INSERT INTO Users (Username, Password) VALUES (@u, @p)", conn);
                insertCmd.Parameters.AddWithValue("@u", Username);
                insertCmd.Parameters.AddWithValue("@p", Password);
                insertCmd.ExecuteNonQuery();

                TempData["Success"] = "Kayıt başarılı, şimdi giriş yapabilirsin!";
                return RedirectToAction(nameof(Login));
            }

            // GİRİŞ KONTROLÜ
            var cmd = new SqliteCommand("SELECT Id, Username FROM Users WHERE Username=@u AND Password=@p", conn);
            cmd.Parameters.AddWithValue("@u", Username);
            cmd.Parameters.AddWithValue("@p", Password);
            
            using var reader = cmd.ExecuteReader();
            if (reader.Read())
            {
                HttpContext.Session.SetString("UserId", reader["Id"].ToString());
                HttpContext.Session.SetString("Username", reader["Username"].ToString());
                return RedirectToAction("Index", "Home");
            }

            TempData["Error"] = "Hatalı giriş!";
            return RedirectToAction(nameof(Login));
        }
    }
}