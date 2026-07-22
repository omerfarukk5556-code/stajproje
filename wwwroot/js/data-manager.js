// SQL'den veri çekip grafiği güncelleyecek şablon kod
async function updateChartWithSqlData() {
    // 1. Kullanıcının seçtiği tablo ve kolonları buradan al
    const requestData = {
        Table: "HIST_TREND",
        Columns: ["FL1", "TEMP1", "PRES1"],
        Limit: 50
    };

    // 2. Senin Controller'daki GetSeries metoduna istek at
    const response = await fetch('/Data/GetSeries', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(requestData)
    });

    const result = await response.json();

    // 3. Grafiği güncelle (Örneğin 'myChart' senin grafik değişkenin olsun)
    myChart.data.labels = result.labels;
    myChart.data.datasets[0].data = result.series["FL1"];
    myChart.data.datasets[1].data = result.series["TEMP1"];
    myChart.data.datasets[2].data = result.series["PRES1"];
    myChart.update();
}