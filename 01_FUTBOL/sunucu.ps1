# ============================================================
# KÜÇÜK YEREL SUNUCU (Yunus için not)
# ------------------------------------------------------------
# Tarayıcılar güvenlik için, bir sayfanın başka sitelerden
# (ESPN gibi) veri çekmesini bazen engeller. Bu dosya senin
# bilgisayarında küçük bir "aracı" çalıştırır:
#   - http://localhost:8765        -> futbol.html sayfasını verir
#   - http://localhost:8765/oyun.html -> klasördeki diğer sayfaları verir
#   - http://localhost:8765/espn/  -> isteği ESPN'e iletir, cevabı sayfaya getirir
# Kapatmak için açılan siyah pencereyi kapatman yeterli.
# ============================================================

param([switch]$TarayiciAcma)

$port = 8765
$klasor = $PSScriptRoot
$dinleyici = New-Object System.Net.HttpListener
$dinleyici.Prefixes.Add("http://localhost:$port/")
try {
    $dinleyici.Start()
}
catch {
    # Sunucu zaten açıksa (BASLAT.bat'a iki kez tıklandıysa) sadece sayfayı aç
    Write-Host "Sunucu zaten acik, sayfa aciliyor." -ForegroundColor Yellow
    if (-not $TarayiciAcma) { Start-Process "http://localhost:$port" }
    exit
}

Write-Host "Futbol sayfasi calisiyor: http://localhost:$port" -ForegroundColor Green
Write-Host "Kapatmak icin bu pencereyi kapat."
if (-not $TarayiciAcma) { Start-Process "http://localhost:$port" }

while ($dinleyici.IsListening) {
    $baglam = $dinleyici.GetContext()
    $istek = $baglam.Request
    $cevap = $baglam.Response
    $yol = $istek.Url.AbsolutePath

    try {
        if ($yol.StartsWith("/espn/")) {
            # ESPN'e ilet
            $hedef = "https://site.api.espn.com/" + $yol.Substring(6) + $istek.Url.Query
            $veri = (New-Object System.Net.WebClient)
            $veri.Encoding = [System.Text.Encoding]::UTF8
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($veri.DownloadString($hedef))
            $cevap.ContentType = "application/json; charset=utf-8"
        }
        else {
            # Sayfayı ver (adres boşsa futbol.html, değilse istenen .html dosyası)
            $dosya = if ($yol -eq "/") { "futbol.html" } else { $yol.TrimStart("/") }
            $tamYol = Join-Path $klasor $dosya
            if ($dosya -notmatch '^[\w-]+\.html$' -or -not (Test-Path $tamYol)) {
                $cevap.StatusCode = 404
                $cevap.Close()
                continue
            }
            $bytes = [System.IO.File]::ReadAllBytes($tamYol)
            $cevap.ContentType = "text/html; charset=utf-8"
        }
        $cevap.OutputStream.Write($bytes, 0, $bytes.Length)
    }
    catch {
        $cevap.StatusCode = 502
    }
    $cevap.Close()
}
