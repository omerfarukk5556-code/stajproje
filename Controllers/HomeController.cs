using System.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using StajWebProjesi.Models;

namespace StajWebProjesi.Controllers;

public class HomeController : Controller
{
    private bool IsAuthenticated()
    {
        return !string.IsNullOrEmpty(HttpContext.Session.GetString("UserId"));
    }

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
