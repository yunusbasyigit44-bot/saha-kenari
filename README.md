# CLAUDE PROJELER — Proje Dizini

Bu dosya klasörün "pano"sudur (5S - Seiketsu). Her yeni proje buraya bir satır olarak eklenir.

## Projeler

| No | Klasör | Ne işe yarar | Nasıl açılır |
|----|--------|--------------|--------------|
| 01 | `01_FUTBOL/` | Canlı (ESPN) futbol istatistikleri + "İpucu Avı" oyunu | `01_FUTBOL/BASLAT.bat` dosyasına çift tıkla |
| 01 | `01_FUTBOL/paylasim/` | Paylaşılabilir sürüm "Saha Kenarı" (claude.ai'de yayında) | https://claude.ai/artifact/AFtHoPZWDuCvCTawcYya6X · Veri yenilemek: `veri_guncelle.ps1` |

## Klasör kuralları (5S)

- **Seiri (Ayıkla):** Kullanılmayan dosya silinmez, `_arsiv/` klasörüne taşınır.
- **Seiton (Düzenle):** Her proje kendi numaralı klasöründe: `01_`, `02_`, `03_` ...
- **Seiso (Temizle):** Geçici/deneme dosyaları proje klasörüne konmaz.
- **Seiketsu (Standartlaştır):** Her proje klasöründe çalıştırma dosyası (`BASLAT.bat` gibi) en üst seviyededir; bu tabloya bir satır eklenir.
- **Shitsuke (Sürdür):** Her iş bitince bu tablo ve klasör düzeni kontrol edilir.

## Arşivler

- `_ARSIV/` — tamamen bırakılan projeler buraya taşınır.
- `01_FUTBOL/_arsiv/galatasaray.html` — ilk sabit verili Galatasaray sayfası (yerini canlı `futbol.html` aldı).
