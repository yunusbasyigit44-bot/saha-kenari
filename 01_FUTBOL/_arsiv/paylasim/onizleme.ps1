# ============================================================
# YEREL ÖNİZLEME (Yunus için not)
# ------------------------------------------------------------
# Saha Kenarı sitesini yayınlamadan önce kendi bilgisayarında
# GitHub Pages'teki haliyle görmek için:
#   powershell -ExecutionPolicy Bypass -File onizleme.ps1
# sonra tarayıcıda http://localhost:8766 adresini aç.
# index.html'i GitHub'daki gibi tam bir sayfaya çevirip verir;
# data.json, gorseller.json ve fikstur.json dosyalarını da verir.
# Kapatmak için pencereyi kapat.
# ============================================================

$port = if ($env:PORT) { [int]$env:PORT } else { 8766 }
$klasor = $PSScriptRoot
$dinleyici = New-Object System.Net.HttpListener
$dinleyici.Prefixes.Add("http://localhost:$port/")
$dinleyici.Start()
Write-Host "Onizleme calisiyor: http://localhost:$port" -ForegroundColor Green

$bas = '<!doctype html><html lang="tr"><head><meta charset="utf-8">' +
       '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">' +
       '<style>body{margin:0}img{max-width:100%}[hidden]{display:none!important}</style></head><body>'
$son = '</body></html>'
$utf8 = New-Object System.Text.UTF8Encoding($false)

while ($dinleyici.IsListening) {
    $baglam = $dinleyici.GetContext()
    $yol = $baglam.Request.Url.AbsolutePath
    $cevap = $baglam.Response
    try {
        if ($yol -eq "/" -or $yol -eq "/index.html") {
            $html = [System.IO.File]::ReadAllText((Join-Path $klasor "index.html"), $utf8)
            $bytes = $utf8.GetBytes($bas + $html + $son)
            $cevap.ContentType = "text/html; charset=utf-8"
        }
        elseif ($yol -match '^/(data|gorseller|fikstur)\.json$') {
            $bytes = [System.IO.File]::ReadAllBytes((Join-Path $klasor $yol.TrimStart("/")))
            $cevap.ContentType = "application/json; charset=utf-8"
        }
        else { $cevap.StatusCode = 404; $cevap.Close(); continue }
        $cevap.OutputStream.Write($bytes, 0, $bytes.Length)
    }
    catch { $cevap.StatusCode = 500 }
    $cevap.Close()
}
