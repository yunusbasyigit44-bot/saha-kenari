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
