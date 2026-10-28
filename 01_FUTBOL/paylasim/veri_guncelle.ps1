# ============================================================
# VERİ GÜNCELLEME (Yunus için not)
# ------------------------------------------------------------
# Paylaşılan sayfa internetteki ESPN'e kendisi bağlanamıyor
# (claude.ai güvenlik için buna izin vermiyor). Bu yüzden:
#   1) Bu script ESPN'den 10 ligin tüm verisini indirir
#   2) data.json (istatistikler) ve gorseller.json (logo + bayraklar) dosyalarına yazar
#   3) Sayfa yeniden yayınlanınca herkes güncel veriyi görür
# Her gün otomatik çalışacak şekilde ayarlandı. Elle çalıştırmak için:
#   powershell -ExecutionPolicy Bypass -File veri_guncelle.ps1
# ============================================================

$ErrorActionPreference = "Stop"
$klasor = $PSScriptRoot

$LIGLER = [ordered]@{
    "tur.1" = "Trendyol Süper Lig"
    "eng.1" = "Premier League"
    "esp.1" = "LaLiga"
    "ita.1" = "Serie A"
    "ger.1" = "Bundesliga"
    "fra.1" = "Ligue 1"
    "por.1" = "Liga Portugal"
    "ned.1" = "Eredivisie"
    "ksa.1" = "Saudi Pro League"
    "usa.1" = "MLS"
}
$API = "https://site.api.espn.com/apis"

$web = New-Object System.Net.WebClient
$web.Encoding = [System.Text.Encoding]::UTF8

function VeriCek($adres) {
    # İnternet bazen takılır: 3 kez dene
    for ($i = 1; $i -le 3; $i++) {
        try { return ($web.DownloadString($adres) | ConvertFrom-Json) }
        catch { if ($i -eq 3) { throw }; Start-Sleep -Seconds 2 }
    }
}

function ResimCek($yol, $boyut) {
    # ESPN'in küçültme servisinden küçük bir PNG al, metne (base64) çevir
    try {
        $b = $web.DownloadData("https://a.espncdn.com/combiner/i?img=$yol&w=$boyut&h=$boyut")
        return "data:image/png;base64," + [Convert]::ToBase64String($b)
    } catch { return "" }
}

function Sayi($s, $ad) { if ($s.ContainsKey($ad)) { [int]$s[$ad] } else { 0 } }

$ligListesi = @()
$takimlar = @{}
$logolar = @{}
$bayraklar = @{}

foreach ($kod in $LIGLER.Keys) {
    Write-Host "== $($LIGLER[$kod]) ==" -ForegroundColor Cyan

    # Takımlar
    $tv = VeriCek "$API/site/v2/sports/soccer/$kod/teams"
    $ligTakimlari = @($tv.sports[0].leagues[0].teams | ForEach-Object { $_.team })

    # Puan durumu
    $pv = VeriCek "$API/v2/sports/soccer/$kod/standings"
    $grup = if ($pv.children) { $pv.children[0] } else { $pv }
    $sezon = $grup.standings.seasonDisplayName
    $puan = @()
    foreach ($e in $grup.standings.entries) {
        $s = @{}; foreach ($st in $e.stats) { $s[$st.name] = $st.value }
        $puan += [ordered]@{
            id = $e.team.id; sira = (Sayi $s "rank"); o = (Sayi $s "gamesPlayed")
            g = (Sayi $s "wins"); b = (Sayi $s "ties"); m = (Sayi $s "losses")
            av = (Sayi $s "pointDifferential"); p = (Sayi $s "points")
        }
    }

    # Kadrolar
    $oyuncular = @()
    foreach ($t in $ligTakimlari) {
        $takimlar[$t.id] = [ordered]@{
            ad = $t.displayName; kisa = $t.shortDisplayName
            renk = $t.color; renk2 = $t.alternateColor; lig = $kod
        }
        if (-not $logolar.ContainsKey($t.id)) {
            $logolar[$t.id] = ResimCek "/i/teamlogos/soccer/500/$($t.id).png" 64
        }

        $kv = VeriCek "$API/site/v2/sports/soccer/$kod/teams/$($t.id)/roster"
        foreach ($a in $kv.athletes) {
            $s = @{}
            foreach ($kat in $a.statistics.splits.categories) { foreach ($st in $kat.stats) { $s[$st.name] = $st.value } }
            $ulke = ""
            if ($a.flag.href -match "/countries/500/(\w+)\.png") {
                $ulke = $Matches[1]
                if (-not $bayraklar.ContainsKey($ulke)) { $bayraklar[$ulke] = ResimCek "/i/teamlogos/countries/500/$ulke.png" 40 }
            }
            $oyuncular += [ordered]@{
                i = $a.displayName; p = $a.position.abbreviation; u = $a.citizenship; uk = $ulke
                y = $a.age; f = $a.jersey; t = $t.id
                mac = (Sayi $s "appearances"); g = (Sayi $s "totalGoals"); a = (Sayi $s "goalAssists")
                s = (Sayi $s "totalShots"); sk = (Sayi $s "yellowCards"); kk = (Sayi $s "redCards")
                kur = (Sayi $s "saves")
            }
        }
        Write-Host "  $($t.displayName): $(@($kv.athletes).Count) oyuncu"
    }

    $ligListesi += [ordered]@{ kod = $kod; ad = $LIGLER[$kod]; sezon = $sezon; puan = $puan; oyuncular = $oyuncular }
}

$veri = [ordered]@{
    guncelleme = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    ligler = $ligListesi
    takimlar = $takimlar
}
$gorseller = [ordered]@{ logo = $logolar; bayrak = $bayraklar }

# BOM'suz UTF-8 olarak yaz (Türkçe karakterler bozulmasın)
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $klasor "data.json"), ($veri | ConvertTo-Json -Depth 8 -Compress), $utf8)
[System.IO.File]::WriteAllText((Join-Path $klasor "gorseller.json"), ($gorseller | ConvertTo-Json -Depth 4 -Compress), $utf8)

$toplam = ($ligListesi | ForEach-Object { $_.oyuncular.Count } | Measure-Object -Sum).Sum
Write-Host "BITTI: $($ligListesi.Count) lig, $($takimlar.Count) takim, $toplam oyuncu" -ForegroundColor Green
