-- ============================================================
-- SAHA KENARI - LİDERLİK TABLOSU KURULUMU (Yunus için not)
-- ------------------------------------------------------------
-- Bu kodun tamamını Supabase > SQL Editor'e yapıştırıp "Run" de.
-- Bir kez çalıştırman yeterli. Tekrar çalıştırırsan zarar vermez.
--
-- Ne kuruyor?
--   1) "skorlar" tablosu: her satır bir oyun sonucu
--   2) Mantık kontrolleri: imkansız puanlar, uzun takma adlar reddedilir
--   3) Güvenlik kuralları: herkes okuyabilir ve ekleyebilir,
--      ama kimse başkasının skorunu değiştiremez ya da silemez
--   4) Hız sınırı: aynı cihaz 10 saniyede en fazla 1 skor gönderebilir
-- ============================================================

create table if not exists public.skorlar (
  id          bigint generated always as identity primary key,
  olusturma   timestamptz not null default now(),
  oyun        text not null check (oyun in ('ipucu', 'gizli', 'seri', 'gunluk')),
  lig         text not null check (char_length(lig) <= 10),
  seviye      text check (seviye is null or seviye in ('kolay', 'orta', 'zor')),
  takma_ad    text not null check (char_length(btrim(takma_ad)) between 2 and 20),
  puan        int  not null check (puan >= 0),
  cihaz       uuid not null,
  gun         date,
  -- Her oyunun ulaşılabilecek en yüksek puanı
  constraint puan_siniri check (
       (oyun in ('ipucu', 'gizli') and puan <= 500)
    or (oyun = 'seri'   and puan <= 300)
    or (oyun = 'gunluk' and puan between 1 and 5 and gun is not null)
  )
);

-- Günün Bulmacası: bir cihaz bir günde sadece bir sonuç gönderebilir
create unique index if not exists skorlar_gunluk_tek
  on public.skorlar (cihaz, gun) where oyun = 'gunluk';

-- Liderlik tablosu sorguları hızlı olsun
create index if not exists skorlar_tablo
  on public.skorlar (oyun, lig, seviye, olusturma desc, puan desc);

-- Hız sınırı ve tarih kontrolü
create or replace function public.skor_kontrol() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.skorlar
             where cihaz = new.cihaz and olusturma > now() - interval '10 seconds') then
    raise exception 'Cok hizli skor gonderimi';
  end if;
  if new.oyun = 'gunluk' and new.gun not between current_date - 1 and current_date + 1 then
    raise exception 'Gecersiz bulmaca tarihi';
  end if;
  new.takma_ad := btrim(new.takma_ad);
  new.olusturma := now();
  return new;
end $$;

drop trigger if exists skor_kontrol on public.skorlar;
create trigger skor_kontrol before insert on public.skorlar
  for each row execute function public.skor_kontrol();

-- Güvenlik kuralları (Row Level Security)
alter table public.skorlar enable row level security;

drop policy if exists "herkes okuyabilir" on public.skorlar;
create policy "herkes okuyabilir" on public.skorlar
  for select to anon, authenticated using (true);

drop policy if exists "herkes ekleyebilir" on public.skorlar;
create policy "herkes ekleyebilir" on public.skorlar
  for insert to anon, authenticated with check (true);

-- Değiştirme ve silme kuralı YOK: yani kimse yapamaz
grant select, insert on public.skorlar to anon, authenticated;

-- ------------------------------------------------------------
-- EK 1 (28 Ekim 2026): Bayrak Turu oyunu eklendi
-- ------------------------------------------------------------
alter table public.skorlar drop constraint if exists skorlar_oyun_check;
alter table public.skorlar add constraint skorlar_oyun_check
  check (oyun in ('ipucu', 'gizli', 'seri', 'gunluk', 'bayrak'));
alter table public.skorlar drop constraint if exists puan_siniri;
alter table public.skorlar add constraint puan_siniri check (
     (oyun in ('ipucu', 'gizli') and puan <= 500)
  or (oyun = 'seri'   and puan <= 300)
  or (oyun = 'gunluk' and puan between 1 and 5 and gun is not null)
  or (oyun = 'bayrak' and puan between 1 and 30)
);

-- ------------------------------------------------------------
-- EK 2 (29 Ekim 2026): SKOR TAHMİNİ + ARKADAŞ LİGLERİ
-- ------------------------------------------------------------
-- Gizlilik: sayfa her kayıtta cihazın gizli kimliğini ("anahtar")
-- gönderir. Veritabanı bunu tek yönlü şifreye (sha256) çevirip
-- "oyuncu" sütununa yazar ve anahtarın kendisini SİLER. Böylece
-- kimse başkasının adına tahmin yapamaz.
--
-- Maç başlayınca tahmin kapanır, iki kat koruma var:
--   1) Sayfa maçın başlama saatini (baslama) gönderir; veritabanı
--      bu saat geçtiyse tahmini REDDEDER.
--   2) Biri baslama'yı sahte gönderse bile: tahminin saati
--      (olusturma) veritabanı tarafından konur ve sayfa puanlarken
--      bunu ESPN'deki gerçek başlama saatiyle karşılaştırır;
--      maçtan sonra yapılan tahmin puan tablosunda sayılmaz.
-- Tahmin değiştirmek = yeni satır eklemek; son tahmin geçerlidir.

create table if not exists public.tahminler (
  id         bigint generated always as identity primary key,
  olusturma  timestamptz not null default now(),
  anahtar    uuid,
  oyuncu     text not null default '',
  takma_ad   text not null check (char_length(btrim(takma_ad)) between 2 and 20),
  mac        text not null check (mac ~ '^[0-9]{1,15}$'),
  lig        text not null check (char_length(lig) <= 10),
  ev         smallint not null check (ev between 0 and 20),
  dep        smallint not null check (dep between 0 and 20),
  baslama    timestamptz not null
);
create index if not exists tahminler_zaman on public.tahminler (olusturma);
create index if not exists tahminler_oyuncu on public.tahminler (oyuncu);

create or replace function public.tahmin_kontrol() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.anahtar is null then raise exception 'Anahtar gerekli'; end if;
  new.oyuncu := encode(sha256(convert_to(new.anahtar::text, 'UTF8')), 'hex');
  new.anahtar := null;
  -- Maç başladıysa tahmin kapalı (ve en fazla 30 gün sonrasına tahmin)
  if now() >= new.baslama then raise exception 'Mac basladi, tahmin kapandi'; end if;
  if new.baslama > now() + interval '30 days' then raise exception 'Gecersiz mac saati'; end if;
  -- Hız sınırı: bir oyuncu dakikada en fazla 60 tahmin
  if (select count(*) from public.tahminler
      where oyuncu = new.oyuncu and olusturma > now() - interval '1 minute') >= 60 then
    raise exception 'Cok hizli tahmin gonderimi';
  end if;
  new.takma_ad := btrim(new.takma_ad);
  new.olusturma := now();
  return new;
end $$;

drop trigger if exists tahmin_kontrol on public.tahminler;
create trigger tahmin_kontrol before insert on public.tahminler
  for each row execute function public.tahmin_kontrol();

alter table public.tahminler enable row level security;
drop policy if exists "herkes okuyabilir" on public.tahminler;
create policy "herkes okuyabilir" on public.tahminler
  for select to anon, authenticated using (true);
drop policy if exists "herkes ekleyebilir" on public.tahminler;
create policy "herkes ekleyebilir" on public.tahminler
  for insert to anon, authenticated with check (true);
grant select, insert on public.tahminler to anon, authenticated;

-- Arkadaş ligleri: 6 haneli kodla katılınır. Tablolar dışarıdan
-- okunamaz (kodlar listelenemesin); ligi sadece kodu bilen,
-- aşağıdaki lig_getir fonksiyonuyla görebilir.
create table if not exists public.ozel_ligler (
  kod        text primary key check (kod ~ '^[A-Z2-9]{6}$'),
  ad         text not null check (char_length(btrim(ad)) between 2 and 30),
  olusturma  timestamptz not null default now(),
  anahtar    uuid,
  kurucu     text not null default ''
);

create table if not exists public.lig_uyeleri (
  id         bigint generated always as identity primary key,
  kod        text not null references public.ozel_ligler (kod),
  olusturma  timestamptz not null default now(),
  anahtar    uuid,
  oyuncu     text not null default '',
  unique (kod, oyuncu)
);

create or replace function public.ozel_lig_kontrol() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.anahtar is null then raise exception 'Anahtar gerekli'; end if;
  new.kurucu := encode(sha256(convert_to(new.anahtar::text, 'UTF8')), 'hex');
  new.anahtar := null;
  if (select count(*) from public.ozel_ligler
      where kurucu = new.kurucu and olusturma > now() - interval '1 day') >= 5 then
    raise exception 'Cok fazla lig';
  end if;
  new.ad := btrim(new.ad);
  new.olusturma := now();
  return new;
end $$;

drop trigger if exists ozel_lig_kontrol on public.ozel_ligler;
create trigger ozel_lig_kontrol before insert on public.ozel_ligler
  for each row execute function public.ozel_lig_kontrol();

create or replace function public.lig_uye_kontrol() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.anahtar is null then raise exception 'Anahtar gerekli'; end if;
  new.oyuncu := encode(sha256(convert_to(new.anahtar::text, 'UTF8')), 'hex');
  new.anahtar := null;
  if (select count(*) from public.lig_uyeleri
      where oyuncu = new.oyuncu and olusturma > now() - interval '1 hour') >= 20 then
    raise exception 'Cok hizli katilim';
  end if;
  new.olusturma := now();
  return new;
end $$;

drop trigger if exists lig_uye_kontrol on public.lig_uyeleri;
create trigger lig_uye_kontrol before insert on public.lig_uyeleri
  for each row execute function public.lig_uye_kontrol();

alter table public.ozel_ligler enable row level security;
alter table public.lig_uyeleri enable row level security;
drop policy if exists "herkes ekleyebilir" on public.ozel_ligler;
create policy "herkes ekleyebilir" on public.ozel_ligler
  for insert to anon, authenticated with check (true);
drop policy if exists "herkes ekleyebilir" on public.lig_uyeleri;
create policy "herkes ekleyebilir" on public.lig_uyeleri
  for insert to anon, authenticated with check (true);
revoke all on public.ozel_ligler, public.lig_uyeleri from anon, authenticated;
grant insert on public.ozel_ligler, public.lig_uyeleri to anon, authenticated;

-- Kodu bilen, ligin adını ve üyelerini (şifreli oyuncu kimlikleri) görür
create or replace function public.lig_getir(p_kod text) returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'kod', l.kod, 'ad', l.ad,
    'uyeler', coalesce((select json_agg(u.oyuncu) from public.lig_uyeleri u where u.kod = l.kod), '[]'::json))
  from public.ozel_ligler l where l.kod = upper(btrim(p_kod));
$$;
grant execute on function public.lig_getir(text) to anon, authenticated;
