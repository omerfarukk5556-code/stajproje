using StajWebProjesi.Models;
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

app.Run();