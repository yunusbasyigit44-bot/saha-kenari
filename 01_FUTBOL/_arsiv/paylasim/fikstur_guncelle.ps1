# ============================================================
# FİKSTÜR GÜNCELLEME (Yunus için not)
# ------------------------------------------------------------
# Skor Tahmini oyunu için 10 ligin maçlarını ESPN'den indirir:
#   - son 4 günün sonuçları + önümüzdeki 10 günün fikstürü
#   - fikstur.json dosyasına EKLER (eski maçlar silinmez, çünkü
#     "tüm zamanlar" puan tablosu geçmiş sonuçlara ihtiyaç duyar)
# Sayfa açıkken seçili ligin skorlarını ESPN'den canlı da tazeler;
# bu dosya diğer liglerin ve geçmiş maçların kaydıdır.
# Elle çalıştırmak için:
#   powershell -ExecutionPolicy Bypass -File fikstur_guncelle.ps1
# ============================================================

$ErrorActionPreference = "Stop"
$klasor = $PSScriptRoot
$dosya = Join-Path $klasor "fikstur.json"

$LIGLER = @("tur.1", "eng.1", "esp.1", "ita.1", "ger.1", "fra.1", "por.1", "ned.1", "ksa.1", "usa.1")
$API = "https://site.api.espn.com/apis/site/v2/sports/soccer"

$web = New-Object System.Net.WebClient
$web.Encoding = [System.Text.Encoding]::UTF8

function VeriCek($adres) {
    for ($i = 1; $i -le 3; $i++) {
        try { return ($web.DownloadString($adres) | ConvertFrom-Json) }
        catch { if ($i -eq 3) { throw }; Start-Sleep -Seconds 2 }
    }
}

# Maç durumu: pre = başlamadı, in = oynanıyor, post = bitti, iptal = ertelendi/iptal
function Durum($tip) {
    if ($tip.name -match "POSTPONED|CANCELED|CANCELLED|ABANDONED|SUSPENDED|FORFEIT") { return "iptal" }
    return $tip.state
}

# Eski kayıtları oku (yoksa boş başla)
$maclar = [ordered]@{}
if (Test-Path $dosya) {
    $eski = [System.IO.File]::ReadAllText($dosya) | ConvertFrom-Json
    foreach ($p in $eski.maclar.PSObject.Properties) { $maclar[$p.Name] = $p.Value }
}
$onceki = $maclar.Count

$bugun = (Get-Date).ToUniversalTime().Date
$hatalar = 0
foreach ($kod in $LIGLER) {
    $sayac = 0
    for ($g = -4; $g -le 10; $g++) {
        $gun = $bugun.AddDays($g).ToString("yyyyMMdd")
        try { $v = VeriCek "$API/$kod/scoreboard?dates=$gun" }
        catch { $hatalar++; Write-Host "  $kod $gun indirilemedi" -ForegroundColor Yellow; continue }
        foreach ($e in $v.events) {
            $c = $e.competitions[0]
            $ev = $c.competitors | Where-Object { $_.homeAway -eq "home" }
            $dep = $c.competitors | Where-Object { $_.homeAway -eq "away" }
            $durum = Durum $e.status.type
            $skorVar = $durum -eq "in" -or $durum -eq "post"
            $maclar[$e.id] = [ordered]@{
                l = $kod; t = $e.date; e = $ev.team.id; d = $dep.team.id
                es = if ($skorVar) { [int]$ev.score } else { $null }
                ds = if ($skorVar) { [int]$dep.score } else { $null }
                s = $durum
            }
            $sayac++
        }
    }
    Write-Host "$kod : $sayac mac"
}

# KALİTE KONTROL: çoğu istek başarısız olduysa dosyaya dokunma
if ($hatalar -gt ($LIGLER.Count * 15) / 2) { throw "Cok fazla istek basarisiz ($hatalar), fikstur kaydedilmedi." }

$veri = [ordered]@{
    guncelleme = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    maclar = $maclar
}
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($dosya, ($veri | ConvertTo-Json -Depth 4 -Compress), $utf8)
Write-Host "BITTI: $($maclar.Count) mac kayitli ($($maclar.Count - $onceki) yeni)" -ForegroundColor Green
