using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.Sqlite;
using StajWebProjesi.Models;
using System.Security.Cryptography;
using System.Text;

namespace StajWebProjesi.Controllers
{
    [AllowAnonymous]
    public class AccountController : Controller
    {
        private string GetConnectionString()
        {
            string dbPath = @"C:\Users\omer\Desktop\staj proje\StajWebProjesi\stajweb.db";
            return $"Data Source={dbPath}";
        }

        private string HashPassword(string password)
        {
            using (var sha256 = SHA256.Create())
            {
                var hashedBytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(password));
                return BitConverter.ToString(hashedBytes).Replace("-", "").ToLower();
            }
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