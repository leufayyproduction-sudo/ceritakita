-- Untuk project baru: jalankan sekali di Supabase SQL Editor.
-- 0001_init.sql
create table profiles(id uuid primary key references auth.users on delete cascade, display_name text, avatar_url text, role text not null default 'user', premium_until timestamptz, created_at timestamptz default now());
create table stories(id uuid primary key default gen_random_uuid(), author_id uuid references profiles, alias text, body text not null, tags text[], status text default 'published', created_at timestamptz default now());
create table mood_entries(id uuid primary key default gen_random_uuid(), user_id uuid references profiles not null, day date not null, score int check(score between 1 and 5), emotions text[], note text, unique(user_id,day));
create table journal_entries(id uuid primary key default gen_random_uuid(), user_id uuid references profiles not null, title text, content text, mood_score int, created_at timestamptz default now());
create table plans(id uuid primary key default gen_random_uuid(), name text, price_idr int, period text, features text[], is_active bool default true);
create table payment_settings(id int primary key default 1, qris_image_url text, merchant_name text, instructions text, expiry_minutes int default 60);
create table orders(id uuid primary key default gen_random_uuid(), user_id uuid references profiles, plan_id uuid references plans, total_amount int, status text default 'pending', proof_url text, created_at timestamptz default now());
create table reviews(id uuid primary key default gen_random_uuid(), user_id uuid references profiles unique, rating int check(rating between 1 and 5), body text, status text default 'published', is_featured bool default false, created_at timestamptz default now());
create or replace function is_admin() returns bool language sql security definer as $$ select exists(select 1 from profiles where id=auth.uid() and role='admin') $$;
alter table profiles enable row level security; alter table stories enable row level security; alter table mood_entries enable row level security; alter table journal_entries enable row level security; alter table orders enable row level security; alter table reviews enable row level security; alter table plans enable row level security; alter table payment_settings enable row level security;
create policy own_profile on profiles for all using(id=auth.uid() or is_admin());
create policy own_mood on mood_entries for all using(user_id=auth.uid());
create policy own_journal on journal_entries for all using(user_id=auth.uid());
create policy own_orders on orders for all using(user_id=auth.uid() or is_admin());
create policy read_stories on stories for select using(status='published' or is_admin());
create policy read_reviews on reviews for select using(status='published' or user_id=auth.uid() or is_admin());
create policy write_reviews on reviews for insert with check(user_id=auth.uid());
create policy admin_reviews on reviews for update using(is_admin());
create policy read_plans on plans for select using(is_active or is_admin());
create policy admin_plans on plans for all using(is_admin());
create policy read_pay on payment_settings for select using(true);
create policy admin_pay on payment_settings for all using(is_admin());

-- 0002_profile_trigger.sql (aman dijalankan ulang secara terpisah)
begin;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, split_part(new.email, '@', 1))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

insert into public.profiles (id, display_name)
select users.id, split_part(users.email, '@', 1)
from auth.users as users
where not exists (
  select 1 from public.profiles as profiles where profiles.id = users.id
)
on conflict (id) do nothing;

commit;

-- 0003_anonymous_stories.sql
begin;

create table if not exists public.story_reactions (
  story_id uuid not null references public.stories(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  type text not null check (type in ('peluk','semangat','aku_juga')),
  created_at timestamptz not null default now(),
  primary key (story_id,user_id,type)
);
create table if not exists public.story_comments (
  id uuid primary key default gen_random_uuid(),
  story_id uuid not null references public.stories(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  alias text not null,
  body text not null check (char_length(btrim(body)) between 1 and 1000),
  status text not null default 'published' check (status in ('published','hidden','removed')),
  needs_moderation boolean not null default false,
  created_at timestamptz not null default now()
);
create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  target_type text not null check (target_type in ('story','comment')),
  target_id uuid not null,
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  reason text not null check (reason in ('spam','sara','kekerasan','lainnya')),
  detail text not null default '' check (char_length(detail) <= 1000),
  status text not null default 'open' check (status in ('open','handled','dismissed')),
  handled_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (target_type,target_id,reporter_id)
);
alter table public.stories add column if not exists needs_moderation boolean not null default false;
update public.stories
set alias = (array['Kupu-kupu','Awan','Bintang','Daun','Embun'])[1+floor(random()*5)::int] || ' ' || (array['Tenang','Hangat','Berani','Lembut','Ceria'])[1+floor(random()*5)::int] || ' ' || substr(gen_random_uuid()::text,1,4)
where alias is null or btrim(alias) = '';

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public
as $$ select exists(select 1 from public.profiles where id=auth.uid() and role='admin') $$;

create index if not exists stories_author_created_idx on public.stories(author_id,created_at);
create index if not exists story_comments_story_created_idx on public.story_comments(story_id,created_at);
create index if not exists story_comments_author_created_idx on public.story_comments(author_id,created_at);
create index if not exists reports_reporter_created_idx on public.reports(reporter_id,created_at);

create table if not exists public.site_settings (key text primary key, value jsonb not null);
insert into public.site_settings(key,value) values ('crisis_help', '{"label":"Healing119.id — dukungan psikologis Kemenkes","url":"https://healing119.id","phone":"119 ekstensi 8","emergency":"119","source":"https://kesprimkom.kemkes.go.id/konten/127/151/0/cegah-bunuh-diri-dukung-kesehatan-jiwa-kenali-layanan-healing119-id"}'::jsonb) on conflict (key) do nothing;

alter table public.story_reactions enable row level security;
alter table public.story_comments enable row level security;
alter table public.reports enable row level security;
alter table public.site_settings enable row level security;

-- Identity-bearing base tables are not readable by browser roles.
revoke all on public.stories, public.story_comments from anon, authenticated;
grant insert (author_id,body) on public.stories to authenticated;
grant insert (story_id,author_id,body) on public.story_comments to authenticated;
revoke all on public.story_reactions, public.reports, public.site_settings from anon, authenticated;
grant select, delete on public.story_reactions to authenticated;
grant insert (story_id,user_id,type) on public.story_reactions to authenticated;
grant select on public.reports to authenticated;
grant insert (target_type,target_id,reporter_id,reason,detail) on public.reports to authenticated;
grant select on public.site_settings to authenticated;

-- Keep the existing profile policy from allowing users to promote their own role.
revoke insert, update on public.profiles from authenticated, anon;
grant insert (id,display_name,avatar_url) on public.profiles to authenticated;
grant update (display_name,avatar_url) on public.profiles to authenticated;

create or replace function public.story_is_published(target uuid)
returns boolean language sql stable security definer set search_path = public
as $$ select exists(select 1 from public.stories where id = target and status = 'published') $$;
revoke all on function public.story_is_published(uuid) from public;
grant execute on function public.story_is_published(uuid) to authenticated;

drop policy if exists write_own_story on public.stories;
create policy write_own_story on public.stories for insert to authenticated with check (author_id = auth.uid() and status in ('published','hidden'));
drop policy if exists read_own_reactions on public.story_reactions;
create policy read_own_reactions on public.story_reactions for select to authenticated using (user_id = auth.uid());
drop policy if exists react_published_story on public.story_reactions;
create policy react_published_story on public.story_reactions for insert to authenticated with check (user_id = auth.uid() and public.story_is_published(story_id));
drop policy if exists delete_own_reaction on public.story_reactions;
create policy delete_own_reaction on public.story_reactions for delete to authenticated using (user_id = auth.uid());
drop policy if exists comment_published_story on public.story_comments;
create policy comment_published_story on public.story_comments for insert to authenticated with check (author_id = auth.uid() and public.story_is_published(story_id) and status in ('published','hidden'));
drop policy if exists report_own on public.reports;
create policy report_own on public.reports for select to authenticated using (reporter_id = auth.uid() or public.is_admin());
drop policy if exists report_insert on public.reports;
create policy report_insert on public.reports for insert to authenticated with check (reporter_id = auth.uid() and status = 'open' and handled_by is null);
drop policy if exists crisis_help_read on public.site_settings;
create policy crisis_help_read on public.site_settings for select to authenticated using (key = 'crisis_help');

create or replace function public.guard_story_content()
returns trigger language plpgsql security definer set search_path = public
as $$
declare n integer;
begin
  if auth.uid() is null or new.author_id <> auth.uid() then raise exception 'Akses ditolak'; end if;
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text, 0));
  if tg_table_name = 'stories' then
    if char_length(btrim(new.body)) not between 1 and 5000 then raise exception 'Cerita tidak valid'; end if;
    select count(*) into n from public.stories where author_id = auth.uid() and created_at > now() - interval '1 hour';
    if n >= 5 then raise exception 'Batas cerita tercapai'; end if;
  else
    select count(*) into n from public.story_comments where author_id = auth.uid() and created_at > now() - interval '1 minute';
    if n >= 5 then raise exception 'Batas komentar tercapai'; end if;
  end if;
  new.body := btrim(new.body);
  new.alias := (array['Kupu-kupu','Awan','Bintang','Daun','Embun'])[1+floor(random()*5)::int] || ' ' || (array['Tenang','Hangat','Berani','Lembut','Ceria'])[1+floor(random()*5)::int] || ' ' || substr(gen_random_uuid()::text,1,4);
  new.needs_moderation := new.body ~* '(bunuh[[:space:]]+diri|menyakiti[[:space:]]+diri|mengakhiri[[:space:]]+hidup|ingin[[:space:]]+mati|bangsat|bajingan)';
  new.status := case when new.needs_moderation then 'hidden' else 'published' end;
  return new;
end;
$$;
drop trigger if exists guard_story_insert on public.stories;
create trigger guard_story_insert before insert on public.stories for each row execute function public.guard_story_content();
drop trigger if exists guard_comment_insert on public.story_comments;
create trigger guard_comment_insert before insert on public.story_comments for each row execute function public.guard_story_content();

create or replace function public.queue_story_moderation()
returns trigger language plpgsql security definer set search_path = public
as $$ begin
  if new.needs_moderation then
    insert into public.reports(target_type,target_id,reporter_id,reason,detail)
    values (case when tg_table_name = 'stories' then 'story' else 'comment' end, new.id, new.author_id, 'lainnya', 'Ditandai otomatis: perlu tinjauan dukungan/moderasi.')
    on conflict (target_type,target_id,reporter_id) do nothing;
  end if;
  return new;
end; $$;
drop trigger if exists queue_story_moderation on public.stories;
create trigger queue_story_moderation after insert on public.stories for each row execute function public.queue_story_moderation();
drop trigger if exists queue_comment_moderation on public.story_comments;
create trigger queue_comment_moderation after insert on public.story_comments for each row execute function public.queue_story_moderation();

create or replace function public.guard_story_report()
returns trigger language plpgsql security definer set search_path = public
as $$ declare n integer; begin
  if auth.uid() is null or new.reporter_id <> auth.uid() then raise exception 'Akses ditolak'; end if;
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text, 0));
  select count(*) into n from public.reports where reporter_id = auth.uid() and created_at > now() - interval '1 minute';
  if n >= 5 then raise exception 'Batas laporan tercapai'; end if;
  if new.target_type = 'story' then
    if not exists(select 1 from public.stories where id = new.target_id and (status = 'published' or (author_id = auth.uid() and needs_moderation))) then raise exception 'Cerita tidak tersedia'; end if;
  else
    if not exists(select 1 from public.story_comments where id = new.target_id and ((status = 'published' and public.story_is_published(story_id)) or (author_id = auth.uid() and needs_moderation))) then raise exception 'Komentar tidak tersedia'; end if;
  end if;
  return new;
end; $$;
drop trigger if exists guard_report_insert on public.reports;
create trigger guard_report_insert before insert on public.reports for each row execute function public.guard_story_report();

-- These owner-executed views intentionally expose only anonymous published data.
create or replace view public.story_feed with (security_barrier = true) as
select s.id, coalesce(s.alias,'Teman Bercerita') as alias, s.body,
  (s.created_at at time zone 'Asia/Jakarta')::date as day,
  (select count(*) from public.story_reactions r where r.story_id=s.id and r.type='peluk') as peluk,
  (select count(*) from public.story_reactions r where r.story_id=s.id and r.type='semangat') as semangat,
  (select count(*) from public.story_reactions r where r.story_id=s.id and r.type='aku_juga') as aku_juga,
  exists(select 1 from public.story_reactions r where r.story_id=s.id and r.user_id=auth.uid() and r.type='peluk') as my_peluk,
  exists(select 1 from public.story_reactions r where r.story_id=s.id and r.user_id=auth.uid() and r.type='semangat') as my_semangat,
  exists(select 1 from public.story_reactions r where r.story_id=s.id and r.user_id=auth.uid() and r.type='aku_juga') as my_aku_juga
from public.stories s where s.status='published' and auth.uid() is not null
order by s.created_at desc,s.id desc;
create or replace view public.story_comment_feed with (security_barrier = true) as
select recent.id,recent.story_id,recent.alias,recent.body,
  (recent.created_at at time zone 'Asia/Jakarta')::date as day
from (
  select c.id,c.story_id,c.alias,c.body,c.created_at,
    row_number() over (partition by c.story_id order by c.created_at desc,c.id desc) as position
  from public.story_comments c join public.stories s on s.id=c.story_id
  where c.status='published' and s.status='published' and auth.uid() is not null
) as recent
where recent.position <= 5
order by recent.created_at desc,recent.id desc;
revoke all on public.story_feed, public.story_comment_feed from public, anon, authenticated;
grant select on public.story_feed, public.story_comment_feed to authenticated;

commit;

-- 0004_education.sql
begin;

create table if not exists public.articles (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  title text not null check (char_length(btrim(title)) between 1 and 200),
  excerpt text not null default '',
  content text not null,
  category text not null check (char_length(btrim(category)) between 1 and 80),
  status text not null default 'draft' check (status in ('draft','published','hidden')),
  published_at timestamptz default now(),
  created_at timestamptz not null default now()
);
create table if not exists public.videos (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(btrim(title)) between 1 and 200),
  youtube_url text not null,
  youtube_id text not null unique check (youtube_id ~ '^[A-Za-z0-9_-]{11}$'),
  category text not null check (char_length(btrim(category)) between 1 and 80),
  status text not null default 'draft' check (status in ('draft','published','hidden')),
  published_at timestamptz default now(),
  created_at timestamptz not null default now()
);
create index if not exists articles_status_published_idx on public.articles(status,published_at desc);
create index if not exists videos_status_published_idx on public.videos(status,published_at desc);

create or replace function public.set_youtube_video_id()
returns trigger language plpgsql set search_path = public
as $$ declare extracted text; begin
  extracted := substring(new.youtube_url from '^https://youtu\.be/([A-Za-z0-9_-]{11})(?:[?&#/]|$)');
  if extracted is null then
    extracted := substring(new.youtube_url from '^https://(?:www\.|m\.)?youtube\.com/(?:embed/|shorts/|live/)([A-Za-z0-9_-]{11})(?:[?&#/]|$)');
  end if;
  if extracted is null and new.youtube_url ~ '^https://(?:www\.|m\.)?youtube\.com/watch\?' then
    extracted := substring(new.youtube_url from '[?&]v=([A-Za-z0-9_-]{11})(?:[&#]|$)');
  end if;
  if extracted is null then raise exception 'Link YouTube tidak valid'; end if;
  new.youtube_id := extracted;
  return new;
end; $$;
drop trigger if exists set_youtube_video_id on public.videos;
create trigger set_youtube_video_id before insert or update on public.videos for each row execute function public.set_youtube_video_id();

alter table public.articles enable row level security;
alter table public.videos enable row level security;
revoke all on public.articles,public.videos from anon,authenticated;
grant select on public.articles,public.videos to anon,authenticated;
grant insert,update,delete on public.articles,public.videos to authenticated;

drop policy if exists articles_public_read on public.articles;
create policy articles_public_read on public.articles for select to anon,authenticated using (status='published' and published_at <= now());
drop policy if exists articles_admin_manage on public.articles;
create policy articles_admin_manage on public.articles for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists videos_public_read on public.videos;
create policy videos_public_read on public.videos for select to anon,authenticated using (status='published' and published_at <= now());
drop policy if exists videos_admin_manage on public.videos;
create policy videos_admin_manage on public.videos for all to authenticated using (public.is_admin()) with check (public.is_admin());

insert into public.articles(slug,title,excerpt,content,category,status,published_at) values
('memberi-nama-pada-perasaan','Memberi nama pada perasaan','Mulai mengenali apa yang sedang hadir, tanpa harus buru-buru mengubahnya.',
$article$Kadang kita hanya bisa bilang, “Aku sedang tidak baik.” Kamu boleh mulai dari sana. Coba berhenti sejenak dan tanyakan pada diri sendiri: apakah ada lelah, sedih, kecewa, atau rasa lain yang muncul?

Tidak ada jawaban yang harus sempurna. Jika sulit menemukan kata, tulis apa yang terjadi hari ini dan bagaimana rasanya bagimu. Kamu juga boleh memilih lebih dari satu perasaan.

Catatan kecil ini bisa menjadi awal percakapan dengan dirimu. Jika perasaan terasa terlalu berat untuk dihadapi sendiri, berbicaralah dengan orang tepercaya atau tenaga profesional.$article$,
'Kenali Diri','published',now()),
('jurnal-tiga-kalimat','Jurnal pertama, cukup tiga kalimat','Tidak perlu tulisan panjang untuk memberi ruang pada ceritamu.',
$article$Halaman kosong kadang membuat kita bingung harus mulai dari mana. Coba tulis tiga kalimat sederhana: “Hari ini aku mengalami…”, “Aku merasa…”, dan “Besok aku ingin memberi diriku…”.

Kamu bisa menulis tentang hal biasa: perjalanan pulang, percakapan singkat, atau waktu istirahat. Jurnal tidak harus berisi sesuatu yang besar dan tidak perlu dibaca orang lain.

Kalau belum ingin menulis, tidak apa-apa. Simpan pertanyaannya dan kembali saat kamu merasa siap. Ritmemu boleh berbeda setiap hari.$article$,
'Journaling','published',now()),
('jeda-kecil-hari-padat','Memberi ruang untuk jeda kecil','Satu pilihan sederhana untuk menemani hari yang terasa penuh.',
$article$Di hari yang padat, kamu boleh mencari jeda yang terasa masuk akal untukmu. Mungkin meletakkan ponsel sebentar, duduk di tempat yang nyaman, atau menikmati minuman tanpa mengerjakan hal lain.

Tanyakan pada diri sendiri: “Apa yang aku butuhkan sekarang?” Jawabannya bisa sesederhana makan, beristirahat, atau menghubungi teman. Tidak semua kebutuhan harus diselesaikan sekaligus.

Jeda bukan tuntutan baru. Pilih yang cocok dengan situasimu, dan tinggalkan yang tidak membantu.$article$,
'Self-care','published',now())
on conflict (slug) do nothing;

-- Video asli TED; judul UI Indonesia, bahasa video Inggris.
insert into public.videos(title,youtube_url,category,status,published_at) values
('Memahami stres bersama Kelly McGonigal · TED','https://www.youtube.com/watch?v=RcGyVTAoXEU','Kenali Diri','published',now()),
('Mengapa kita tidur? Russell Foster · TED','https://www.youtube.com/watch?v=LWULB9Aoopc','Self-care','published',now())
on conflict (youtube_id) do nothing;

commit;

-- 0005_premium_payments.sql
begin;

alter table public.plans add column if not exists slug text;
create unique index if not exists plans_slug_unique on public.plans(slug);
alter table public.payment_settings add column if not exists unique_code_enabled boolean not null default true;
alter table public.payment_settings add column if not exists provider_label text not null default 'DANA';
alter table public.orders add column if not exists base_amount integer;
alter table public.orders add column if not exists unique_code integer not null default 0;
alter table public.orders add column if not exists expires_at timestamptz;
alter table public.orders add column if not exists qris_image_url text;
alter table public.orders add column if not exists merchant_name text;
alter table public.orders add column if not exists instructions text;
alter table public.orders add column if not exists note text;
update public.orders set base_amount=coalesce(total_amount,0) where base_amount is null;
update public.orders set expires_at=coalesce(created_at,now()) + interval '60 minutes' where expires_at is null;
alter table public.orders alter column expires_at set not null;
alter table public.orders drop constraint if exists orders_unique_code_check;
alter table public.orders add constraint orders_unique_code_check check (unique_code=0 or unique_code between 100 and 999);
create index if not exists orders_user_created_idx on public.orders(user_id,created_at desc);

insert into public.plans(slug,name,price_idr,period,features,is_active) values
('gratis','Gratis',0,'free',array['Cerita anonim','Mood harian','Jurnal privat','Edukasi publik'],false),
('bulanan','Bulanan',49000,'monthly',array['Semua fitur Gratis','Akses Premium selama 1 bulan'],true),
('tahunan','Tahunan',399000,'yearly',array['Semua fitur Gratis','Akses Premium selama 1 tahun'],true)
on conflict (slug) do nothing;
-- QRIS harus diisi dengan gambar merchant asli; tidak menggunakan QRIS rekaan.
insert into public.payment_settings(id,merchant_name,instructions,expiry_minutes) values
(1,'CeritaKita','Bayar melalui aplikasi yang mendukung QRIS dengan nominal tepat, lalu unggah bukti. Pembayaran diverifikasi manual.',60)
on conflict (id) do nothing;

-- Users may read their own orders but cannot set prices or payment status.
drop policy if exists own_orders on public.orders;
drop policy if exists orders_owner_read on public.orders;
create policy orders_owner_read on public.orders for select to authenticated using (user_id=auth.uid() or public.is_admin());
drop policy if exists orders_admin_update on public.orders;
create policy orders_admin_update on public.orders for update to authenticated using (public.is_admin()) with check (public.is_admin());
revoke all on public.orders from anon,authenticated;
grant select,update on public.orders to authenticated;

create or replace function public.expire_my_orders()
returns void language plpgsql security definer set search_path = public
as $$ begin
  if auth.uid() is null then raise exception 'Masuk terlebih dahulu'; end if;
  update public.orders set status='expired'
  where user_id=auth.uid() and status in ('pending','rejected') and expires_at <= now();
end; $$;
revoke all on function public.expire_my_orders() from public;
grant execute on function public.expire_my_orders() to authenticated;

create or replace function public.create_premium_order(selected_plan uuid)
returns uuid language plpgsql security definer set search_path = public
as $$
declare p record; settings record; code integer; order_id uuid; existing uuid; expiry integer; attempts integer := 0;
begin
  if auth.uid() is null then raise exception 'Masuk terlebih dahulu'; end if;
  perform pg_advisory_xact_lock(hashtextextended('ceritakita-payment-orders',0));
  perform public.expire_my_orders();
  select id into existing from public.orders where user_id=auth.uid() and plan_id=selected_plan and status in ('pending','rejected') and expires_at>now() order by created_at desc limit 1;
  if existing is not null then return existing; end if;
  if exists(select 1 from public.orders where user_id=auth.uid() and status in ('pending','awaiting_verification','rejected')) then raise exception 'Selesaikan pesanan sebelumnya dulu, ya.'; end if;
  if (select count(*) from public.orders where user_id=auth.uid() and created_at>now()-interval '1 day') >= 5 then raise exception 'Maksimal 5 pesanan per hari.'; end if;
  select id,name,slug,price_idr,period,features,is_active into p from public.plans where id=selected_plan and is_active;
  if p.id is null or p.period not in ('monthly','yearly') or p.price_idr is null or p.price_idr<=0 or p.price_idr>2000000000 then raise exception 'Paket tidak tersedia'; end if;
  select id,qris_image_url,merchant_name,instructions,expiry_minutes,unique_code_enabled,provider_label into settings from public.payment_settings where id=1;
  if settings.qris_image_url is null or settings.qris_image_url !~ '^https://' then raise exception 'QRIS belum tersedia'; end if;
  expiry := greatest(1,least(coalesce(settings.expiry_minutes,60),1440));
  code := 0;
  if settings.unique_code_enabled then
    loop
      code := 100+floor(random()*900)::integer;
      exit when not exists(select 1 from public.orders where total_amount=p.price_idr+code and status in ('pending','awaiting_verification','rejected'));
      attempts := attempts+1;
      if attempts>=1800 then raise exception 'Kode pembayaran sedang penuh. Coba lagi nanti.'; end if;
    end loop;
  end if;
  insert into public.profiles(id,display_name) select auth.uid(),split_part(email,'@',1) from auth.users where id=auth.uid() on conflict(id) do nothing;
  insert into public.orders(user_id,plan_id,base_amount,unique_code,total_amount,status,expires_at,qris_image_url,merchant_name,instructions)
  values(auth.uid(),p.id,p.price_idr,code,p.price_idr+code,'pending',now()+make_interval(mins=>expiry),settings.qris_image_url,settings.merchant_name,settings.instructions)
  returning id into order_id;
  return order_id;
end; $$;
revoke all on function public.create_premium_order(uuid) from public;
grant execute on function public.create_premium_order(uuid) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('proofs','proofs',false,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists proofs_owner_read on storage.objects;
create policy proofs_owner_read on storage.objects for select to authenticated using (
  bucket_id='proofs' and ((storage.foldername(name))[1]=auth.uid()::text or public.is_admin())
);
drop policy if exists proofs_owner_upload on storage.objects;
create policy proofs_owner_upload on storage.objects for insert to authenticated with check (
  bucket_id='proofs' and (storage.foldername(name))[1]=auth.uid()::text and exists(
    select 1 from public.orders o where o.id::text=(storage.foldername(name))[2] and o.user_id=auth.uid() and o.status in ('pending','rejected') and o.expires_at>now()
  )
);
drop policy if exists proofs_owner_cleanup on storage.objects;
create policy proofs_owner_cleanup on storage.objects for delete to authenticated using (
  bucket_id='proofs' and (storage.foldername(name))[1]=auth.uid()::text and not exists(select 1 from public.orders o where o.proof_url=name)
);

create or replace function public.submit_order_proof(order_id uuid, proof_path text)
returns void language plpgsql security definer set search_path = public
as $$ declare current_order record; begin
  if auth.uid() is null then raise exception 'Masuk terlebih dahulu'; end if;
  select id,user_id,plan_id,total_amount,status,proof_url,created_at,base_amount,unique_code,expires_at,qris_image_url,merchant_name,instructions,note into current_order
  from public.orders where id=order_id and user_id=auth.uid() for update;
  if current_order.id is null or current_order.status not in ('pending','rejected') or current_order.expires_at<=now() then raise exception 'Pesanan tidak bisa menerima bukti'; end if;
  if proof_path not like auth.uid()::text || '/' || order_id::text || '/%' or not exists(select 1 from storage.objects where bucket_id='proofs' and name=proof_path) then raise exception 'Bukti tidak valid'; end if;
  update public.orders set proof_url=proof_path,status='awaiting_verification',note=null where id=order_id;
end; $$;
revoke all on function public.submit_order_proof(uuid,text) from public;
grant execute on function public.submit_order_proof(uuid,text) to authenticated;

commit;

-- 0006_reviews.sql
begin;

alter table public.reviews add column if not exists title text not null default '';
alter table public.reviews add column if not exists photos text[] not null default '{}';
alter table public.reviews add column if not exists helpful_count integer not null default 0;
alter table public.reviews add column if not exists admin_note text;
alter table public.reviews drop constraint if exists reviews_title_length;
alter table public.reviews add constraint reviews_title_length check(char_length(title)<=120);
alter table public.reviews drop constraint if exists reviews_photos_limit;
alter table public.reviews add constraint reviews_photos_limit check(cardinality(photos)<=3);
create table if not exists public.review_votes (
  review_id uuid not null references public.reviews(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  primary key(review_id,user_id)
);
create index if not exists reviews_status_created_idx on public.reviews(status,created_at desc);
alter table public.review_votes enable row level security;
revoke all on public.reviews,public.review_votes from anon,authenticated;
grant select on public.reviews to authenticated;
grant insert(user_id,rating,title,body) on public.reviews to authenticated;
grant update(rating,title,body) on public.reviews to authenticated;
grant delete on public.reviews to authenticated;
grant select,delete on public.review_votes to authenticated;
grant insert(review_id,user_id) on public.review_votes to authenticated;

drop policy if exists read_reviews on public.reviews;
create policy read_reviews on public.reviews for select to authenticated using(user_id=auth.uid() or public.is_admin());
drop policy if exists write_reviews on public.reviews;
create policy write_reviews on public.reviews for insert to authenticated with check(user_id=auth.uid());
drop policy if exists admin_reviews on public.reviews;
drop policy if exists edit_own_review on public.reviews;
create policy edit_own_review on public.reviews for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
drop policy if exists delete_own_review on public.reviews;
create policy delete_own_review on public.reviews for delete to authenticated using(user_id=auth.uid());

create or replace function public.review_is_published(target uuid)
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.reviews where id=target and status='published') $$;
revoke all on function public.review_is_published(uuid) from public;
grant execute on function public.review_is_published(uuid) to authenticated;
drop policy if exists review_votes_own_read on public.review_votes;
create policy review_votes_own_read on public.review_votes for select to authenticated using(user_id=auth.uid());
drop policy if exists review_votes_own_insert on public.review_votes;
create policy review_votes_own_insert on public.review_votes for insert to authenticated with check(user_id=auth.uid() and public.review_is_published(review_id));
drop policy if exists review_votes_own_delete on public.review_votes;
create policy review_votes_own_delete on public.review_votes for delete to authenticated using(user_id=auth.uid());

create or replace function public.guard_review_write()
returns trigger language plpgsql security definer set search_path=public
as $$ begin
  if auth.uid() is null or new.user_id<>auth.uid() then raise exception 'Akses ditolak'; end if;
  if new.rating is null or new.rating not between 1 and 5 or char_length(btrim(coalesce(new.title,''))) not between 1 and 120 or char_length(btrim(coalesce(new.body,''))) not between 1 and 2000 then raise exception 'Review tidak valid'; end if;
  new.title:=btrim(new.title); new.body:=btrim(new.body);
  if tg_op='UPDATE' and old.status in ('hidden','removed') then new.status:=old.status;
  else new.status:=case when (new.title || ' ' || new.body) ~* '(bangsat|bajingan|https?://|bunuh[[:space:]]+diri|menyakiti[[:space:]]+diri)' then 'pending' else 'published' end;
  end if;
  return new;
end; $$;
drop trigger if exists guard_review_write on public.reviews;
create trigger guard_review_write before insert or update of title,body,rating on public.reviews for each row execute function public.guard_review_write();

create or replace function public.update_review_helpful_count()
returns trigger language plpgsql security definer set search_path=public
as $$ begin
  if tg_op='INSERT' then update public.reviews set helpful_count=helpful_count+1 where id=new.review_id; return new;
  else update public.reviews set helpful_count=greatest(0,helpful_count-1) where id=old.review_id; return old; end if;
end; $$;
drop trigger if exists update_review_helpful_count on public.review_votes;
create trigger update_review_helpful_count after insert or delete on public.review_votes for each row execute function public.update_review_helpful_count();
update public.reviews r set helpful_count=(select count(*) from public.review_votes v where v.review_id=r.id);

-- Extend the existing report infrastructure without changing story/comment rules.
alter table public.reports drop constraint if exists reports_target_type_check;
alter table public.reports add constraint reports_target_type_check check(target_type in ('story','comment','review'));
create or replace function public.guard_story_report()
returns trigger language plpgsql security definer set search_path=public
as $$ declare n integer; begin
  if auth.uid() is null or new.reporter_id<>auth.uid() then raise exception 'Akses ditolak'; end if;
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
  select count(*) into n from public.reports where reporter_id=auth.uid() and created_at>now()-interval '1 minute';
  if n>=5 then raise exception 'Batas laporan tercapai'; end if;
  if new.target_type='story' then
    if not exists(select 1 from public.stories where id=new.target_id and (status='published' or (author_id=auth.uid() and needs_moderation))) then raise exception 'Cerita tidak tersedia'; end if;
  elsif new.target_type='comment' then
    if not exists(select 1 from public.story_comments where id=new.target_id and ((status='published' and public.story_is_published(story_id)) or (author_id=auth.uid() and needs_moderation))) then raise exception 'Komentar tidak tersedia'; end if;
  elsif new.target_type='review' then
    if not public.review_is_published(new.target_id) then raise exception 'Review tidak tersedia'; end if;
  else raise exception 'Target tidak valid'; end if;
  return new;
end; $$;

create or replace view public.review_feed with(security_barrier=true) as
select r.id,'Teman ' || substr(r.id::text,1,6) as name,r.rating,r.title,r.body,r.photos,r.is_featured,
  r.helpful_count,(r.created_at at time zone 'Asia/Jakarta')::date as day,
  exists(select 1 from public.review_votes v where v.review_id=r.id and v.user_id=auth.uid()) as voted
from public.reviews r where r.status='published' and r.rating between 1 and 5 order by r.created_at desc,r.id desc;
revoke all on public.review_feed from public,anon,authenticated;
grant select on public.review_feed to anon,authenticated;

commit;

-- 0007_security_feed_audit.sql
begin;

-- Audit the live public schema, including application tables absent from old migrations.
-- Extension-owned tables are managed by their extensions and are left untouched.
do $$
declare target record;
begin
  for target in
    select ns.nspname, cls.relname
    from pg_class cls join pg_namespace ns on ns.oid=cls.relnamespace
    where ns.nspname='public' and cls.relkind in ('r','p') and not cls.relrowsecurity
      and not exists (
        select 1 from pg_depend dep
        where dep.classid='pg_class'::regclass and dep.objid=cls.oid and dep.deptype='e'
      )
  loop
    execute format('alter table %I.%I enable row level security',target.nspname,target.relname);
  end loop;
end;
$$;

-- Block direct identity access even if an earlier setup added column grants.
revoke select on public.stories,public.story_comments from public,anon,authenticated;
revoke select(author_id) on public.stories from public,anon,authenticated;
revoke select(author_id) on public.story_comments from public,anon,authenticated;

-- Recreate without CASCADE so unexpected dependent objects are not removed.
-- DROP is necessary: CREATE OR REPLACE cannot remove leaked columns from a live view.
drop view if exists public.story_feed;
drop view if exists public.story_comment_feed;
drop view if exists public.review_feed;

-- Owner-executed views are intentional: identities stay unreadable in base tables,
-- while only these explicit published projections are exposed to API roles.
create or replace view public.story_feed with(security_barrier=true) as
select s.id,coalesce(s.alias,'Teman Bercerita') as alias,s.body,
  (s.created_at at time zone 'Asia/Jakarta')::date as day,
  (select count(*) from public.story_reactions r where r.story_id=s.id and r.type='peluk') as peluk,
  (select count(*) from public.story_reactions r where r.story_id=s.id and r.type='semangat') as semangat,
  (select count(*) from public.story_reactions r where r.story_id=s.id and r.type='aku_juga') as aku_juga,
  exists(select 1 from public.story_reactions r where r.story_id=s.id and r.user_id=auth.uid() and r.type='peluk') as my_peluk,
  exists(select 1 from public.story_reactions r where r.story_id=s.id and r.user_id=auth.uid() and r.type='semangat') as my_semangat,
  exists(select 1 from public.story_reactions r where r.story_id=s.id and r.user_id=auth.uid() and r.type='aku_juga') as my_aku_juga
from public.stories s
where s.status='published' and auth.uid() is not null
order by s.created_at desc,s.id desc;

create or replace view public.story_comment_feed with(security_barrier=true) as
select recent.id,recent.story_id,recent.alias,recent.body,
  (recent.created_at at time zone 'Asia/Jakarta')::date as day
from (
  select c.id,c.story_id,c.alias,c.body,c.created_at,
    row_number() over(partition by c.story_id order by c.created_at desc,c.id desc) as position
  from public.story_comments c join public.stories s on s.id=c.story_id
  where c.status='published' and s.status='published' and auth.uid() is not null
) as recent
where recent.position<=5
order by recent.created_at desc,recent.id desc;

create or replace view public.review_feed with(security_barrier=true) as
select r.id,'Teman ' || substr(r.id::text,1,6) as name,r.rating,r.title,r.body,r.photos,r.is_featured,
  r.helpful_count,(r.created_at at time zone 'Asia/Jakarta')::date as day,
  exists(select 1 from public.review_votes v where v.review_id=r.id and v.user_id=auth.uid()) as voted
from public.reviews r
where r.status='published' and r.rating between 1 and 5
order by r.created_at desc,r.id desc;

revoke all on public.story_feed,public.story_comment_feed,public.review_feed from public,anon,authenticated;
grant select on public.story_feed,public.story_comment_feed to authenticated;
grant select on public.review_feed to anon,authenticated;

-- Enforce exact output contracts in the live database before committing.
do $$
declare contract record; actual text[];
begin
  for contract in
    select 'story_feed'::text as view_name,
      array['id','alias','body','day','peluk','semangat','aku_juga','my_peluk','my_semangat','my_aku_juga']::text[] as columns
    union all select 'story_comment_feed',array['id','story_id','alias','body','day']::text[]
    union all select 'review_feed',array['id','name','rating','title','body','photos','is_featured','helpful_count','day','voted']::text[]
  loop
    select array_agg(attr.attname::text order by attr.attnum) into actual
    from pg_attribute attr
    where attr.attrelid=to_regclass(format('public.%I',contract.view_name))
      and attr.attnum>0 and not attr.attisdropped;
    if actual is distinct from contract.columns then
      raise exception 'Kolom view % tidak sesuai kontrak publik',contract.view_name;
    end if;
  end loop;
end;
$$;

commit;

begin;
insert into public.plans(slug,name,price_idr,period,features,is_active) values
('gratis','Gratis',0,'free',array['Cerita anonim','Mood harian','Jurnal privat','Edukasi publik'],false),
('plus','Plus',9000,'monthly',array['Mood tracker lanjutan','Riwayat tanpa batas'],true),
('premium','Premium',15000,'monthly',array['Semua fitur Plus','Insight mendalam','Konten premium'],true),
('pro','Pro',20000,'monthly',array['Semua fitur Premium','Rekomendasi personal','Konsultasi ahli terjadwal'],true)
on conflict(slug) do update set name=excluded.name,price_idr=excluded.price_idr,period=excluded.period,features=excluded.features,is_active=excluded.is_active;
update public.plans set is_active=false where slug is null or slug not in ('gratis','plus','premium','pro');
-- Preserve historical payment amounts; only new orders use the new cap.
alter table public.orders add column if not exists legacy_pricing boolean not null default false;
update public.orders set legacy_pricing=true where unique_code>99 or base_amount>20000;
update public.orders set status='expired' where legacy_pricing and status in ('pending','rejected');
alter table public.orders drop constraint if exists orders_unique_code_check;
alter table public.orders add constraint orders_unique_code_check check(legacy_pricing or unique_code between 0 and 99);
alter table public.orders drop constraint if exists orders_new_total_check;
alter table public.orders add constraint orders_new_total_check check(legacy_pricing or (total_amount=base_amount+unique_code and total_amount between 0 and 20099));
create or replace function public.create_premium_order(selected_plan uuid)
returns uuid language plpgsql security definer set search_path = public
as $$
declare p record; settings record; code integer; order_id uuid; existing uuid; expiry integer;
begin
  if auth.uid() is null then raise exception 'Masuk terlebih dahulu'; end if;
  perform pg_advisory_xact_lock(hashtextextended('ceritakita-payment-orders',0));
  perform public.expire_my_orders();
  select id into existing from public.orders where user_id=auth.uid() and plan_id=selected_plan and status in ('pending','rejected') and expires_at>now() order by created_at desc limit 1;
  if existing is not null then return existing; end if;
  if exists(select 1 from public.orders where user_id=auth.uid() and status in ('pending','awaiting_verification','rejected')) then raise exception 'Selesaikan pesanan sebelumnya dulu, ya.'; end if;
  if (select count(*) from public.orders where user_id=auth.uid() and created_at>now()-interval '1 day') >= 5 then raise exception 'Maksimal 5 pesanan per hari.'; end if;
  select id,name,slug,price_idr,period,features,is_active into p from public.plans where id=selected_plan and is_active;
  if p.id is null or p.period <> 'monthly' or p.price_idr is null or p.price_idr<9000 or p.price_idr>20000 then raise exception 'Paket tidak tersedia'; end if;
  select id,qris_image_url,merchant_name,instructions,expiry_minutes,unique_code_enabled,provider_label into settings from public.payment_settings where id=1;
  if settings.qris_image_url is null or settings.qris_image_url !~ '^https://' then raise exception 'QRIS belum tersedia'; end if;
  expiry := greatest(1,least(coalesce(settings.expiry_minutes,60),1440));
  code := 0;
  if settings.unique_code_enabled then
    select candidate into code from generate_series(1,99) candidate
    where not exists(select 1 from public.orders where total_amount=p.price_idr+candidate and status in ('pending','awaiting_verification','rejected'))
    order by random() limit 1;
    if code is null then raise exception 'Kode pembayaran sedang penuh. Coba lagi nanti.'; end if;
  end if;
  insert into public.profiles(id,display_name) select auth.uid(),split_part(email,'@',1) from auth.users where id=auth.uid() on conflict(id) do nothing;
  insert into public.orders(user_id,plan_id,base_amount,unique_code,total_amount,status,expires_at,qris_image_url,merchant_name,instructions)
  values(auth.uid(),p.id,p.price_idr,code,p.price_idr+code,'pending',now()+make_interval(mins=>expiry),settings.qris_image_url,settings.merchant_name,settings.instructions)
  returning id into order_id;
  return order_id;
end; $$;
revoke all on function public.create_premium_order(uuid) from public;
grant execute on function public.create_premium_order(uuid) to authenticated;


insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('avatars','avatars',false,2097152,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists avatars_owner_read on storage.objects;
create policy avatars_owner_read on storage.objects for select to authenticated using(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists avatars_owner_insert on storage.objects;
create policy avatars_owner_insert on storage.objects for insert to authenticated with check(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists avatars_owner_update on storage.objects;
create policy avatars_owner_update on storage.objects for update to authenticated using(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text) with check(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists avatars_owner_delete on storage.objects;
create policy avatars_owner_delete on storage.objects for delete to authenticated using(bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);
-- Old foreign keys prevented deleting profiles/auth users.
alter table public.stories drop constraint if exists stories_author_id_fkey;
alter table public.stories add constraint stories_author_id_fkey foreign key(author_id) references public.profiles(id) on delete cascade;
alter table public.mood_entries drop constraint if exists mood_entries_user_id_fkey;
alter table public.mood_entries add constraint mood_entries_user_id_fkey foreign key(user_id) references public.profiles(id) on delete cascade;
alter table public.journal_entries drop constraint if exists journal_entries_user_id_fkey;
alter table public.journal_entries add constraint journal_entries_user_id_fkey foreign key(user_id) references public.profiles(id) on delete cascade;
alter table public.orders drop constraint if exists orders_user_id_fkey;
alter table public.orders add constraint orders_user_id_fkey foreign key(user_id) references public.profiles(id) on delete cascade;
alter table public.reviews drop constraint if exists reviews_user_id_fkey;
alter table public.reviews add constraint reviews_user_id_fkey foreign key(user_id) references public.profiles(id) on delete cascade;

create or replace function public.remove_deleted_target_reports() returns trigger language plpgsql security definer set search_path=public as $$
begin
 delete from public.reports where target_id=old.id and target_type=case TG_TABLE_NAME when 'stories' then 'story' when 'story_comments' then 'comment' else 'review' end;
 return old;
end; $$;
revoke all on function public.remove_deleted_target_reports() from public;
drop trigger if exists remove_target_reports on public.stories;
create trigger remove_target_reports after delete on public.stories for each row execute function public.remove_deleted_target_reports();
drop trigger if exists remove_target_reports on public.story_comments;
create trigger remove_target_reports after delete on public.story_comments for each row execute function public.remove_deleted_target_reports();
drop trigger if exists remove_target_reports on public.reviews;
create trigger remove_target_reports after delete on public.reviews for each row execute function public.remove_deleted_target_reports();

create or replace function public.export_my_stories()
returns table(id uuid,alias text,body text,tags text[],status text,created_at timestamptz)
language sql security definer set search_path=public as $$
 select s.id,s.alias,s.body,s.tags,s.status,s.created_at from public.stories s where s.author_id=auth.uid();
$$;
revoke all on function public.export_my_stories() from public;
grant execute on function public.export_my_stories() to authenticated;
create or replace function public.account_storage_files(target_user uuid)
returns table(bucket_id text,name text) language sql security definer set search_path=public as $$
 select o.bucket_id,o.name from storage.objects o where (storage.foldername(o.name))[1]=target_user::text;
$$;
revoke all on function public.account_storage_files(uuid) from public,anon,authenticated;
grant execute on function public.account_storage_files(uuid) to service_role;
commit;

begin;
create table if not exists public.admin_login_limits (
 ip_hash text primary key check(length(ip_hash)=64),
 window_start timestamptz not null default now(),
 attempts integer not null default 0 check(attempts between 0 and 5),
 attempted_at timestamptz[] not null default array[]::timestamptz[]
);
alter table public.admin_login_limits add column if not exists attempted_at timestamptz[] not null default array[]::timestamptz[];
alter table public.admin_login_limits enable row level security;
revoke all on public.admin_login_limits from public,anon,authenticated;
grant all on public.admin_login_limits to service_role;
create or replace function public.consume_admin_login(ip_hash text)
returns boolean language plpgsql security definer set search_path=public as $$
declare current_limit public.admin_login_limits%rowtype; recent timestamptz[];
begin
 if ip_hash is null or ip_hash !~ '^[0-9a-f]{64}$' then return false; end if;
 delete from public.admin_login_limits where window_start<now()-interval '1 day';
 insert into public.admin_login_limits(ip_hash) values(consume_admin_login.ip_hash) on conflict do nothing;
 select l.* into current_limit from public.admin_login_limits l where l.ip_hash=consume_admin_login.ip_hash for update;
 select coalesce(array_agg(t order by t),array[]::timestamptz[]) into recent
 from unnest(current_limit.attempted_at) t where t>now()-interval '10 minutes';
 if cardinality(recent)>=5 then return false; end if;
 recent:=array_append(recent,now());
 update public.admin_login_limits l set attempts=cardinality(recent),attempted_at=recent,window_start=now() where l.ip_hash=consume_admin_login.ip_hash;
 return true;
end; $$;
revoke all on function public.consume_admin_login(text) from public,anon,authenticated;
grant execute on function public.consume_admin_login(text) to service_role;
create table if not exists public.audit_logs (
 id uuid primary key default gen_random_uuid(),
 actor_id uuid references public.profiles(id) on delete set null,
 action text not null,
 target text,
 meta jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);
alter table public.audit_logs enable row level security;
revoke all on public.audit_logs from public,anon,authenticated;
grant select on public.audit_logs to authenticated;
grant all on public.audit_logs to service_role;
drop policy if exists audit_logs_admin_read on public.audit_logs;
create policy audit_logs_admin_read on public.audit_logs for select to authenticated using(public.is_admin());
create index if not exists audit_logs_created_idx on public.audit_logs(created_at desc);
commit;

begin;
alter table public.plans add column if not exists is_highlighted boolean not null default false;
alter table public.plans add column if not exists sort integer not null default 0;
alter table public.plans add column if not exists type text not null default 'subscription';
alter table public.plans enable row level security;
revoke insert,update,delete on public.plans from anon,authenticated;
grant select on public.plans to anon,authenticated;
create table if not exists public.media (
 id uuid primary key default gen_random_uuid(),path text not null unique,url text not null,
 name text not null default '',alt text not null default '',size bigint not null check(size between 1 and 5242880),
 mime text not null check(mime in ('image/jpeg','image/png','image/webp')),
 uploaded_by uuid references public.profiles(id) on delete cascade,
 created_at timestamptz not null default now(),deleting boolean not null default false
);
alter table public.media add column if not exists name text not null default '';
alter table public.media add column if not exists deleting boolean not null default false;
alter table public.media enable row level security;
revoke all on public.media from public,anon,authenticated;
grant select on public.media to authenticated;
drop policy if exists media_admin_read on public.media;
create policy media_admin_read on public.media for select to authenticated using(public.is_admin());
create table if not exists public.site_settings(key text primary key,value jsonb not null);
alter table public.site_settings enable row level security;
revoke insert,update,delete on public.site_settings from anon,authenticated;
grant select on public.site_settings to anon,authenticated;
drop policy if exists site_settings_public_read on public.site_settings;
create policy site_settings_public_read on public.site_settings for select to anon,authenticated using(true);
drop policy if exists site_settings_admin_write on public.site_settings;
create policy site_settings_admin_write on public.site_settings for all to authenticated using(public.is_admin()) with check(public.is_admin());
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('media','media',true,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=true,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists media_public_read on storage.objects;
create policy media_public_read on storage.objects for select to anon,authenticated using(bucket_id='media');
drop policy if exists media_admin_insert on storage.objects;
create policy media_admin_insert on storage.objects for insert to authenticated with check(bucket_id='media' and public.is_admin() and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists media_admin_update on storage.objects;
create policy media_admin_update on storage.objects for update to authenticated using(bucket_id='media' and public.is_admin()) with check(bucket_id='media' and public.is_admin());
drop policy if exists media_admin_delete on storage.objects;
create policy media_admin_delete on storage.objects for delete to authenticated using(bucket_id='media' and public.is_admin());
create or replace function public.record_admin_audit(audit_action text,audit_target text,audit_meta jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
 if length(audit_action) not between 1 and 100 or length(audit_target)>200 or audit_meta is null or jsonb_typeof(audit_meta)<>'object' or octet_length(audit_meta::text)>128000 then raise exception 'Audit tidak valid'; end if;
 insert into public.audit_logs(actor_id,action,target,meta) values(auth.uid(),audit_action,audit_target,audit_meta);
end; $$;
create or replace function public.admin_save_plan(payload jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare plan_id uuid; feature_list text[]; old_plan jsonb;
begin
 if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
 if payload is null or jsonb_typeof(payload)<>'object' or octet_length(payload::text)>20000 then raise exception 'Paket tidak valid'; end if;
 if coalesce(length(trim(payload->>'name')),0) not between 1 and 80 or coalesce(payload->>'slug','') !~ '^[a-z0-9]+(-[a-z0-9]+)*$' or length(payload->>'slug')>80 then raise exception 'Paket tidak valid'; end if;
 if coalesce(payload->>'period','') not in ('free','monthly','yearly') or coalesce(payload->>'price_idr','') !~ '^[0-9]+$' or (payload->>'price_idr')::bigint>20000 then raise exception 'Harga tidak valid'; end if;
 if ((payload->>'period')='free' and (payload->>'price_idr')::integer<>0) or ((payload->>'period')<>'free' and (payload->>'price_idr')::integer<9000) then raise exception 'Harga tidak valid'; end if;
 if jsonb_typeof(payload->'features') is distinct from 'array' or jsonb_array_length(payload->'features')>30 then raise exception 'Fitur tidak valid'; end if;
 if exists(select 1 from jsonb_array_elements(payload->'features') f where jsonb_typeof(f)<>'string' or length(trim(f#>>'{}')) not between 1 and 200) then raise exception 'Fitur tidak valid'; end if;
 select coalesce(array_agg(trim(f)),array[]::text[]) into feature_list from jsonb_array_elements_text(payload->'features') f;
 if jsonb_typeof(payload->'is_active') is distinct from 'boolean' or jsonb_typeof(payload->'is_highlighted') is distinct from 'boolean' or coalesce(payload->>'sort','') !~ '^[0-9]{1,4}$' then raise exception 'Status tidak valid'; end if;
 if nullif(payload->>'id','') is not null then
  plan_id:=(payload->>'id')::uuid;
  select to_jsonb(p) into old_plan from public.plans p where p.id=plan_id for update;
  if old_plan is null then raise exception 'Paket tidak ditemukan'; end if;
  update public.plans set name=trim(payload->>'name'),slug=payload->>'slug',price_idr=(payload->>'price_idr')::integer,period=payload->>'period',features=feature_list,is_active=(payload->>'is_active')::boolean,is_highlighted=(payload->>'is_highlighted')::boolean,sort=(payload->>'sort')::integer where id=plan_id;
 else
  insert into public.plans(name,slug,price_idr,period,features,is_active,is_highlighted,sort) values(trim(payload->>'name'),payload->>'slug',(payload->>'price_idr')::integer,payload->>'period',feature_list,(payload->>'is_active')::boolean,(payload->>'is_highlighted')::boolean,(payload->>'sort')::integer) returning id into plan_id;
 end if;
 perform public.record_admin_audit(case when old_plan is null then 'plan.create' else 'plan.update' end,plan_id::text,jsonb_build_object('before',old_plan,'after',payload));
 return plan_id;
end; $$;
create or replace function public.admin_delete_plan(plan_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare old_plan jsonb;
begin
 if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
 select to_jsonb(p) into old_plan from public.plans p where p.id=plan_id for update;
 if old_plan is null then raise exception 'Paket tidak ditemukan'; end if;
 if exists(select 1 from public.orders o where o.plan_id=admin_delete_plan.plan_id) then raise exception 'Paket masih dipakai pesanan. Nonaktifkan paket saja.'; end if;
 delete from public.plans p where p.id=plan_id;
 perform public.record_admin_audit('plan.delete',plan_id::text,old_plan);
end; $$;
create or replace function public.admin_list_media(query_text text default '',page_number integer default 1)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
 if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
 if query_text is null or length(query_text)>120 or page_number is null or page_number not between 1 and 10000 then raise exception 'Pencarian tidak valid'; end if;
 return jsonb_build_object(
  'total',(select count(*) from public.media m where strpos(lower(m.name||' '||m.alt),lower(trim(query_text)))>0),
  'rows',coalesce((select jsonb_agg(to_jsonb(items) order by items.created_at desc,items.id) from (
    select m.id,m.url,m.path,m.name,m.alt,m.size,m.mime,m.created_at,m.deleting
    from public.media m where strpos(lower(m.name||' '||m.alt),lower(trim(query_text)))>0
    order by m.created_at desc,m.id limit 24 offset (page_number-1)*24
  ) items),'[]'::jsonb)
 );
end; $$;
revoke all on function public.admin_list_media(text,integer) from public,anon;
grant execute on function public.admin_list_media(text,integer) to authenticated;
create or replace function public.admin_register_media(payload jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare media_id uuid;
begin
 if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
 if coalesce(payload->>'path','') not like auth.uid()::text||'/%' or not exists(select 1 from storage.objects o where o.bucket_id='media' and o.name=payload->>'path') then raise exception 'File tidak valid'; end if;
 if coalesce(payload->>'url','') !~ '^https://' or (payload->>'mime') not in ('image/jpeg','image/png','image/webp') or (payload->>'size')::bigint not between 1 and 5242880 or length(coalesce(payload->>'alt',''))>300 then raise exception 'Media tidak valid'; end if;
 insert into public.media(path,url,name,alt,size,mime,uploaded_by) values(payload->>'path',payload->>'url',left(coalesce(payload->>'name',''),200),coalesce(payload->>'alt',''),(payload->>'size')::bigint,payload->>'mime',auth.uid()) returning id into media_id;
 perform public.record_admin_audit('media.upload',media_id::text,jsonb_build_object('path',payload->>'path','size',payload->'size'));
 return media_id;
end; $$;
create or replace function public.admin_update_media_alt(media_id uuid,alt_text text)
returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
 if alt_text is null or length(alt_text)>300 then raise exception 'Alt maksimal 300 karakter'; end if;
 update public.media m set alt=trim(alt_text) where m.id=media_id and not m.deleting;
 if not found then raise exception 'Media tidak ditemukan'; end if;
 perform public.record_admin_audit('media.alt',media_id::text,jsonb_build_object('alt',trim(alt_text)));
end; $$;
create or replace function public.admin_media_in_use(media_id uuid)
returns boolean language plpgsql security definer set search_path=public as $$
declare item public.media%rowtype; tab record; used boolean;
begin
 if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
 select * into item from public.media m where m.id=media_id;
 if item.id is null then raise exception 'Media tidak ditemukan'; end if;
 for tab in select c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p') and c.relname not in ('media','audit_logs','admin_login_limits') loop
  execute format('select exists(select 1 from public.%I t where strpos(to_jsonb(t)::text,$1)>0 or strpos(to_jsonb(t)::text,$2)>0)',tab.relname) into used using item.url,item.path;
  if used then return true; end if;
 end loop;
 return false;
end; $$;
create or replace function public.admin_prepare_media_delete(media_id uuid)
returns text language plpgsql security definer set search_path=public as $$
declare storage_path text;
begin
 if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
 perform pg_advisory_xact_lock(hashtextextended('ceritakita-media-references',0));
 select m.path into storage_path from public.media m where m.id=media_id for update;
 if storage_path is null then raise exception 'Media tidak ditemukan'; end if;
 if public.admin_media_in_use(media_id) then raise exception 'Gambar masih dipakai. Ganti gambar pada konten terlebih dahulu.'; end if;
 update public.media m set deleting=true where m.id=media_id;
 return storage_path;
end; $$;
create or replace function public.admin_finish_media_delete(media_id uuid,cancel_delete boolean default false)
returns void language plpgsql security definer set search_path=public as $$
declare old_media jsonb;
begin
 if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
 if cancel_delete then update public.media m set deleting=false where m.id=media_id; return; end if;
 select to_jsonb(m) into old_media from public.media m where m.id=media_id and m.deleting for update;
 if old_media is null then raise exception 'Media tidak ditemukan'; end if;
 if exists(select 1 from storage.objects o where o.bucket_id='media' and o.name=old_media->>'path') then raise exception 'File belum terhapus'; end if;
 delete from public.media m where m.id=media_id;
 perform public.record_admin_audit('media.delete',media_id::text,old_media);
end; $$;
create or replace function public.admin_save_site_settings(settings jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare image_url text; old_value jsonb;
begin
 if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
 if settings is null or jsonb_typeof(settings)<>'object' or octet_length(settings::text)>32000 then raise exception 'Pengaturan tidak valid'; end if;
 if coalesce(length(trim(settings->>'name')),0) not between 1 and 80 or coalesce(settings->>'whatsappNumber','') !~ '^[0-9]{8,15}$' then raise exception 'Identitas atau WhatsApp tidak valid'; end if;
 if jsonb_typeof(settings->'socials') is distinct from 'array' or jsonb_typeof(settings->'chips') is distinct from 'array' or jsonb_typeof(settings->'emergencyContacts') is distinct from 'array' or jsonb_typeof(settings->'stats') is distinct from 'object' then raise exception 'Pengaturan tidak lengkap'; end if;
 perform pg_advisory_xact_lock(hashtextextended('ceritakita-media-references',0));
 foreach image_url in array array[settings->>'logoUrl',settings->>'faviconUrl'] loop
  if image_url is null then raise exception 'Gambar tidak valid'; end if;
  if image_url not in ('/logo-mark.png','/icon.png') and not exists(select 1 from public.media m where m.url=image_url and not m.deleting) then raise exception 'Pilih gambar yang masih tersedia di library'; end if;
 end loop;
 select value into old_value from public.site_settings where key='public_settings' for update;
 insert into public.site_settings(key,value) values('public_settings',settings) on conflict(key) do update set value=excluded.value;
 perform public.record_admin_audit('settings.update','site',jsonb_build_object('before',old_value,'after',settings));
end; $$;
revoke all on function public.record_admin_audit(text,text,jsonb) from public,anon;
grant execute on function public.record_admin_audit(text,text,jsonb) to authenticated;
revoke all on function public.admin_save_plan(jsonb) from public,anon;
grant execute on function public.admin_save_plan(jsonb) to authenticated;
revoke all on function public.admin_delete_plan(uuid) from public,anon;
grant execute on function public.admin_delete_plan(uuid) to authenticated;
revoke all on function public.admin_register_media(jsonb) from public,anon;
grant execute on function public.admin_register_media(jsonb) to authenticated;
revoke all on function public.admin_update_media_alt(uuid,text) from public,anon;
grant execute on function public.admin_update_media_alt(uuid,text) to authenticated;
revoke all on function public.admin_media_in_use(uuid) from public,anon;
grant execute on function public.admin_media_in_use(uuid) to authenticated;
revoke all on function public.admin_prepare_media_delete(uuid) from public,anon;
grant execute on function public.admin_prepare_media_delete(uuid) to authenticated;
revoke all on function public.admin_finish_media_delete(uuid,boolean) from public,anon;
grant execute on function public.admin_finish_media_delete(uuid,boolean) to authenticated;
revoke all on function public.admin_save_site_settings(jsonb) from public,anon;
grant execute on function public.admin_save_site_settings(jsonb) to authenticated;
create or replace function public.create_premium_order(selected_plan uuid)
returns uuid language plpgsql security definer set search_path = public
as $$
declare p record; settings record; code integer; order_id uuid; existing uuid; expiry integer;
begin
  if auth.uid() is null then raise exception 'Masuk terlebih dahulu'; end if;
  perform pg_advisory_xact_lock(hashtextextended('ceritakita-payment-orders',0));
  perform public.expire_my_orders();
  select id into existing from public.orders where user_id=auth.uid() and plan_id=selected_plan and status in ('pending','rejected') and expires_at>now() order by created_at desc limit 1;
  if existing is not null then return existing; end if;
  if exists(select 1 from public.orders where user_id=auth.uid() and status in ('pending','awaiting_verification','rejected')) then raise exception 'Selesaikan pesanan sebelumnya dulu, ya.'; end if;
  if (select count(*) from public.orders where user_id=auth.uid() and created_at>now()-interval '1 day') >= 5 then raise exception 'Maksimal 5 pesanan per hari.'; end if;
  select id,name,slug,price_idr,period,features,is_active into p from public.plans where id=selected_plan and is_active for share;
  if p.id is null or p.period not in ('monthly','yearly') or p.price_idr is null or p.price_idr<9000 or p.price_idr>20000 then raise exception 'Paket tidak tersedia'; end if;
  select id,qris_image_url,merchant_name,instructions,expiry_minutes,unique_code_enabled,provider_label into settings from public.payment_settings where id=1 for share;
  if settings.qris_image_url is null or settings.qris_image_url !~ '^https://' then raise exception 'QRIS belum tersedia'; end if;
  expiry := greatest(1,least(coalesce(settings.expiry_minutes,60),1440));
  code := 0;
  if settings.unique_code_enabled then
    select candidate into code from generate_series(1,99) candidate
    where not exists(select 1 from public.orders where total_amount=p.price_idr+candidate and status in ('pending','awaiting_verification','rejected'))
    order by random() limit 1;
    if code is null then raise exception 'Kode pembayaran sedang penuh. Coba lagi nanti.'; end if;
  end if;
  insert into public.profiles(id,display_name) select auth.uid(),split_part(email,'@',1) from auth.users where id=auth.uid() on conflict(id) do nothing;
  insert into public.orders(user_id,plan_id,base_amount,unique_code,total_amount,status,expires_at,qris_image_url,merchant_name,instructions)
  values(auth.uid(),p.id,p.price_idr,code,p.price_idr+code,'pending',now()+make_interval(mins=>expiry),settings.qris_image_url,settings.merchant_name,settings.instructions)
  returning id into order_id;
  return order_id;
end; $$;
revoke all on function public.create_premium_order(uuid) from public;
grant execute on function public.create_premium_order(uuid) to authenticated;


commit;

-- 0011_admin_education.sql
begin;
alter table public.articles add column if not exists cover_url text;
alter table public.articles add column if not exists is_premium boolean not null default false;
alter table public.videos add column if not exists description text not null default '';
alter table public.videos add column if not exists is_premium boolean not null default false;
alter table public.videos add column if not exists sort integer not null default 0;
alter table public.videos drop constraint if exists videos_sort_range;
alter table public.videos add constraint videos_sort_range check(sort between 0 and 100000);

create or replace function public.can_read_premium_education()
returns boolean language sql stable security definer set search_path=public as $$
 select public.is_admin() or exists(select 1 from public.profiles where id=auth.uid() and premium_until>now());
$$;
revoke all on function public.can_read_premium_education() from public;
grant execute on function public.can_read_premium_education() to anon,authenticated;
alter table public.articles enable row level security;
alter table public.videos enable row level security;
drop policy if exists articles_public_read on public.articles;
create policy articles_public_read on public.articles for select to anon,authenticated using(status='published' and published_at<=now() and (not is_premium or public.can_read_premium_education()));
drop policy if exists videos_public_read on public.videos;
create policy videos_public_read on public.videos for select to anon,authenticated using(status='published' and published_at<=now() and (not is_premium or public.can_read_premium_education()));
drop policy if exists articles_admin_manage on public.articles;
create policy articles_admin_manage on public.articles for select to authenticated using(public.is_admin());
drop policy if exists videos_admin_manage on public.videos;
create policy videos_admin_manage on public.videos for select to authenticated using(public.is_admin());
revoke insert,update,delete on public.articles,public.videos from anon,authenticated;
grant select on public.articles,public.videos to anon,authenticated;

-- Owner-executed barrier views intentionally provide public teasers. Protected fields
-- are null unless the current authenticated viewer has an active subscription/admin role.
create or replace view public.education_articles with(security_barrier=true) as
 select id,title,excerpt,category,cover_url,is_premium,published_at,
 (is_premium and not public.can_read_premium_education()) as locked,
 case when not is_premium or public.can_read_premium_education() then content else null end as content
 from public.articles where status='published' and published_at<=now();
create or replace view public.education_videos with(security_barrier=true) as
 select id,title,description,category,is_premium,sort,published_at,
 (is_premium and not public.can_read_premium_education()) as locked,
 case when not is_premium or public.can_read_premium_education() then youtube_id else null end as youtube_id
 from public.videos where status='published' and published_at<=now();
revoke all on public.education_articles,public.education_videos from anon,authenticated;
grant select on public.education_articles,public.education_videos to anon,authenticated;

create or replace function public.admin_save_education(content_kind text,payload jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare content_id uuid; before_row jsonb; after_row jsonb; scheduled timestamptz;
begin
 if not public.is_admin() then raise exception 'Admin required' using errcode='42501';end if;
 if content_kind not in ('articles','videos') or jsonb_typeof(payload)!='object' or octet_length(payload::text)>150000 then raise exception 'Invalid content';end if;
 if char_length(btrim(coalesce(payload->>'title',''))) not between 1 and 200
 or char_length(btrim(coalesce(payload->>'category',''))) not between 1 and 80
 or coalesce(payload->>'status','') not in ('draft','published')
 or jsonb_typeof(payload->'is_premium') is distinct from 'boolean' then raise exception 'Invalid content';end if;
 content_id:=coalesce(nullif(payload->>'id','')::uuid,gen_random_uuid());
 scheduled:=coalesce(nullif(payload->>'published_at','')::timestamptz,now());
 if content_kind='articles' then
  if coalesce(payload->>'slug','') !~ '^[a-z0-9]+(-[a-z0-9]+)*$' or char_length(payload->>'slug')>180
  or char_length(coalesce(payload->>'excerpt',''))>1000 or char_length(btrim(coalesce(payload->>'content',''))) not between 1 and 100000 then raise exception 'Invalid article';end if;
  perform pg_advisory_xact_lock(hashtext('ceritakita-media-references'));
  if nullif(payload->>'cover_url','') is not null and not exists(select 1 from public.media where url=payload->>'cover_url' and not deleting) then raise exception 'Pick a valid media image';end if;
  select to_jsonb(a) into before_row from public.articles a where id=content_id for update;
  if nullif(payload->>'id','') is not null and before_row is null then raise exception 'Content not found';end if;
  insert into public.articles(id,title,slug,excerpt,content,cover_url,category,is_premium,status,published_at)
  values(content_id,btrim(payload->>'title'),payload->>'slug',coalesce(payload->>'excerpt',''),payload->>'content',nullif(payload->>'cover_url',''),btrim(payload->>'category'),(payload->>'is_premium')::boolean,payload->>'status',scheduled)
  on conflict(id) do update set title=excluded.title,slug=excluded.slug,excerpt=excluded.excerpt,content=excluded.content,cover_url=excluded.cover_url,category=excluded.category,is_premium=excluded.is_premium,status=excluded.status,published_at=excluded.published_at;
  select to_jsonb(a) into after_row from public.articles a where id=content_id;
 else
  if coalesce(payload->>'youtube_id','') !~ '^[A-Za-z0-9_-]{11}$'
  or payload->>'youtube_url' is distinct from 'https://www.youtube.com/watch?v='||(payload->>'youtube_id')
  or char_length(coalesce(payload->>'description',''))>1000
  or coalesce(payload->>'sort','') !~ '^[0-9]{1,6}$' or (payload->>'sort')::integer not between 0 and 100000 then raise exception 'Invalid video';end if;
  select to_jsonb(v) into before_row from public.videos v where id=content_id for update;
  if nullif(payload->>'id','') is not null and before_row is null then raise exception 'Content not found';end if;
  insert into public.videos(id,title,youtube_url,youtube_id,description,category,is_premium,status,sort,published_at)
  values(content_id,btrim(payload->>'title'),payload->>'youtube_url',payload->>'youtube_id',coalesce(payload->>'description',''),btrim(payload->>'category'),(payload->>'is_premium')::boolean,payload->>'status',(payload->>'sort')::integer,scheduled)
  on conflict(id) do update set title=excluded.title,youtube_url=excluded.youtube_url,youtube_id=excluded.youtube_id,description=excluded.description,category=excluded.category,is_premium=excluded.is_premium,status=excluded.status,sort=excluded.sort,published_at=excluded.published_at;
  select to_jsonb(v) into after_row from public.videos v where id=content_id;
 end if;
 -- Keep audit snapshots bounded and avoid duplicating article bodies.
 perform public.record_admin_audit('education.'||content_kind||case when before_row is null then '.create' else '.update' end,
 content_id::text,jsonb_build_object('before',before_row-'content','after',after_row-'content'));
 return content_id;
end; $$;

create or replace function public.admin_change_education(content_kind text,content_id uuid,next_status text,remove_content boolean default false)
returns void language plpgsql security definer set search_path=public as $$
declare previous jsonb;
begin
 if not public.is_admin() then raise exception 'Admin required' using errcode='42501';end if;
 if content_kind not in ('articles','videos') or next_status not in ('draft','published') or remove_content is null then raise exception 'Invalid content';end if;
 perform pg_advisory_xact_lock(hashtext('ceritakita-media-references'));
 if content_kind='articles' then
  select to_jsonb(a) into previous from public.articles a where id=content_id for update;
  if previous is null then raise exception 'Content not found';end if;
  if remove_content then delete from public.articles where id=content_id;
  else update public.articles set status=next_status,published_at=coalesce(published_at,now()) where id=content_id;end if;
 else
  select to_jsonb(v) into previous from public.videos v where id=content_id for update;
  if previous is null then raise exception 'Content not found';end if;
  if remove_content then delete from public.videos where id=content_id;
  else update public.videos set status=next_status,published_at=coalesce(published_at,now()) where id=content_id;end if;
 end if;
 perform public.record_admin_audit('education.'||content_kind||case when remove_content then '.delete' else '.status' end,content_id::text,jsonb_build_object('before',previous-'content','status',case when remove_content then null else next_status end));
end; $$;
revoke all on function public.admin_save_education(text,jsonb),public.admin_change_education(text,uuid,text,boolean) from public,anon;
grant execute on function public.admin_save_education(text,jsonb),public.admin_change_education(text,uuid,text,boolean) to authenticated;
commit;

-- 0012_admin_payments.sql
begin;
alter table public.orders add column if not exists verified_by uuid references public.profiles(id) on delete set null;
alter table public.orders add column if not exists verified_at timestamptz;
alter table public.orders add column if not exists plan_period text;
alter table public.orders add column if not exists plan_name text;
update public.orders o set plan_period=p.period,plan_name=p.name from public.plans p where p.id=o.plan_id and (o.plan_period is null or o.plan_name is null);
alter table public.orders drop constraint if exists orders_plan_period_check;
alter table public.orders add constraint orders_plan_period_check check(plan_period in ('free','monthly','yearly'));
create index if not exists orders_status_expires_idx on public.orders(status,expires_at);
create or replace function public.snapshot_order_plan()
returns trigger language plpgsql security definer set search_path=public as $$ begin
 select period,name into new.plan_period,new.plan_name from public.plans where id=new.plan_id;
 return new;
end; $$;
drop trigger if exists snapshot_order_plan on public.orders;
create trigger snapshot_order_plan before insert on public.orders for each row execute function public.snapshot_order_plan();
revoke all on function public.snapshot_order_plan() from public,anon,authenticated;
alter table public.orders enable row level security;
alter table public.payment_settings enable row level security;
drop policy if exists orders_admin_update on public.orders;
revoke insert,update,delete on public.orders,public.payment_settings from anon,authenticated;
grant select on public.orders to authenticated;
grant select on public.payment_settings to anon,authenticated;

create or replace function public.admin_payment_orders(actor uuid,search_email text default '',filter_status text default '',page_number integer default 1,page_size integer default 20)
returns jsonb language plpgsql security definer set search_path=public as $$
declare rows_json jsonb;total_count bigint;
begin
 if not exists(select 1 from public.profiles where id=actor and role='admin') then raise exception 'Admin required' using errcode='42501';end if;
 if search_email is null or char_length(search_email)>254 or filter_status is null or filter_status not in ('','pending','awaiting_verification','paid','rejected','expired') or page_number is null or page_number<1 or page_number>100000 or page_size is null or page_size not between 1 and 1000 then raise exception 'Invalid filter';end if;
 select count(*) into total_count from public.orders o left join auth.users u on u.id=o.user_id where (filter_status='' or o.status=filter_status) and strpos(lower(coalesce(u.email,'')),lower(btrim(search_email)))>0;
 select coalesce(jsonb_agg(to_jsonb(r)),'[]'::jsonb) into rows_json from (
 select o.id,coalesce(u.email,'Akun dihapus') as email,coalesce(o.plan_name,p.name,'Paket tidak tersedia') as plan_name,o.total_amount,o.status,o.created_at,o.expires_at,o.note,(o.proof_url is not null) as has_proof,o.verified_at
 from public.orders o left join auth.users u on u.id=o.user_id left join public.plans p on p.id=o.plan_id
 where (filter_status='' or o.status=filter_status) and strpos(lower(coalesce(u.email,'')),lower(btrim(search_email)))>0
 order by o.created_at desc,o.id desc limit page_size offset (page_number-1)*page_size
 ) r;
 return jsonb_build_object('rows',rows_json,'total',total_count);
end; $$;

create or replace function public.admin_save_qris(actor uuid,settings jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare previous jsonb;minutes integer;
begin
 if not exists(select 1 from public.profiles where id=actor and role='admin') then raise exception 'Admin required' using errcode='42501';end if;
 if jsonb_typeof(settings) is distinct from 'object' or octet_length(settings::text)>16000
 or char_length(btrim(coalesce(settings->>'merchant_name',''))) not between 1 and 120
 or char_length(btrim(coalesce(settings->>'instructions',''))) not between 1 and 5000
 or coalesce(settings->>'expiry_minutes','') !~ '^[0-9]{1,4}$'
 or jsonb_typeof(settings->'unique_code_enabled') is distinct from 'boolean' then raise exception 'Invalid settings';end if;
 minutes:=(settings->>'expiry_minutes')::integer;if minutes not between 1 and 1440 then raise exception 'Invalid expiry';end if;
 perform pg_advisory_xact_lock(hashtext('ceritakita-media-references'));
 if not exists(select 1 from public.media where url=settings->>'qris_image_url' and not deleting) then raise exception 'Select a valid media image';end if;
 select to_jsonb(s) into previous from public.payment_settings s where id=1 for update;
 insert into public.payment_settings(id,qris_image_url,merchant_name,instructions,expiry_minutes,unique_code_enabled,provider_label)
 values(1,settings->>'qris_image_url',btrim(settings->>'merchant_name'),btrim(settings->>'instructions'),minutes,(settings->>'unique_code_enabled')::boolean,'DANA')
 on conflict(id) do update set qris_image_url=excluded.qris_image_url,merchant_name=excluded.merchant_name,instructions=excluded.instructions,expiry_minutes=excluded.expiry_minutes,unique_code_enabled=excluded.unique_code_enabled,provider_label='DANA';
 insert into public.audit_logs(actor_id,action,target,meta) values(actor,'payment.qris.update','payment_settings:1',jsonb_build_object('before',previous,'after',settings));
end; $$;

create or replace function public.admin_verify_payment(actor uuid,order_id uuid,decision text,rejection_reason text default '')
returns jsonb language plpgsql security definer set search_path=public as $$
declare payment public.orders%rowtype;active_until timestamptz;next_until timestamptz;minutes integer;
begin
 if not exists(select 1 from public.profiles where id=actor and role='admin') then raise exception 'Admin required' using errcode='42501';end if;
 if decision is null or decision not in ('paid','rejected') or rejection_reason is null or char_length(rejection_reason)>1000 or (decision='rejected' and btrim(rejection_reason)='') then raise exception 'Invalid decision';end if;
 select * into payment from public.orders where id=order_id for update;
 if payment.id is null or payment.status is distinct from 'awaiting_verification' or payment.proof_url is null
 or payment.proof_url not like payment.user_id::text||'/'||payment.id::text||'/%'
 or not exists(select 1 from storage.objects where bucket_id='proofs' and name=payment.proof_url) then raise exception 'Order is not awaiting verification';end if;
 if decision='paid' then
  if payment.plan_period is null or payment.plan_period not in ('monthly','yearly') then raise exception 'Invalid paid plan period';end if;
  select premium_until into active_until from public.profiles where id=payment.user_id for update;
  if not found then raise exception 'Profile not found';end if;
  next_until:=greatest(coalesce(active_until,now()),now())+case when payment.plan_period='yearly' then interval '1 year' else interval '1 month' end;
  update public.profiles set premium_until=next_until where id=payment.user_id;
  update public.orders set status='paid',note=null,verified_by=actor,verified_at=now() where id=payment.id;
 else
  select greatest(1,least(coalesce(expiry_minutes,60),1440)) into minutes from public.payment_settings where id=1;
  update public.orders set status='rejected',note=btrim(rejection_reason),verified_by=actor,verified_at=now(),expires_at=greatest(expires_at,now()+make_interval(mins=>coalesce(minutes,60))) where id=payment.id;
 end if;
 insert into public.audit_logs(actor_id,action,target,meta) values(actor,'payment.'||decision,payment.id::text,jsonb_build_object('before_status',payment.status,'reason',case when decision='rejected' then btrim(rejection_reason) else null end,'premium_until',next_until));
 return jsonb_build_object('user_id',payment.user_id,'plan_name',payment.plan_name,'premium_until',next_until);
end; $$;

-- Submitted proofs stay in the manual verification queue even after the payment deadline.
create or replace function public.expire_payment_orders()
returns integer language plpgsql security definer set search_path=public as $$
declare changed integer;
begin
 update public.orders set status='expired' where status in ('pending','rejected') and expires_at<=now();
 get diagnostics changed=row_count;
 if changed>0 then insert into public.audit_logs(actor_id,action,target,meta) values(null,'payment.orders.expire','orders',jsonb_build_object('count',changed));end if;
 return changed;
end; $$;
revoke all on function public.admin_payment_orders(uuid,text,text,integer,integer),public.admin_save_qris(uuid,jsonb),public.admin_verify_payment(uuid,uuid,text,text),public.expire_payment_orders() from public,anon,authenticated;
grant execute on function public.admin_payment_orders(uuid,text,text,integer,integer),public.admin_save_qris(uuid,jsonb),public.admin_verify_payment(uuid,uuid,text,text),public.expire_payment_orders() to service_role;
commit;

-- 0013_admin_moderation.sql
begin;
alter table public.profiles add column if not exists suspended_at timestamptz;
alter table public.profiles add column if not exists suspension_reason text;
alter table public.stories add column if not exists admin_note text;
alter table public.story_comments add column if not exists admin_note text;
alter table public.reports add column if not exists handled_at timestamptz;
create index if not exists reports_target_status_idx on public.reports(target_type,target_id,status);

create or replace function public.current_user_suspended()
returns boolean language sql stable security definer set search_path=public as $$ select exists(select 1 from public.profiles where id=auth.uid() and suspended_at is not null); $$;
revoke all on function public.current_user_suspended() from public,anon;
grant execute on function public.current_user_suspended() to authenticated;
create or replace function public.block_suspended_write()
returns trigger language plpgsql security definer set search_path=public as $$ begin
 if public.current_user_suspended() then raise exception 'Akun ditangguhkan' using errcode='42501';end if;
 if tg_op='DELETE' then return old;else return new;end if;
end; $$;
revoke all on function public.block_suspended_write() from public,anon,authenticated;
do $$ declare tbl text;begin
 foreach tbl in array array['stories','story_comments','story_reactions','reports','reviews','review_votes','mood_entries','journal_entries','orders','profiles'] loop
 execute format('drop trigger if exists block_suspended_write on public.%I',tbl);
 execute format('create trigger block_suspended_write before insert or update or delete on public.%I for each row execute function public.block_suspended_write()',tbl);
 end loop;
end; $$;
drop policy if exists suspended_storage_guard on storage.objects;
create policy suspended_storage_guard on storage.objects as restrictive for all to authenticated using(not public.current_user_suspended()) with check(not public.current_user_suspended());

create or replace function public.admin_review_list()
returns jsonb language plpgsql security definer set search_path=public as $$ declare result jsonb;begin
 if not public.is_admin() then raise exception 'Admin required' using errcode='42501';end if;
 select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) into result from (
 select r.id,coalesce(p.display_name,'Teman CeritaKita') as name,coalesce(u.email,'Akun dihapus') as email,r.rating,r.title,r.body,r.status,r.is_featured,r.admin_note,
 (select count(*) from public.reports x where x.target_type='review' and x.target_id=r.id) as report_count,
 (select count(*) from public.reports x where x.target_type='review' and x.target_id=r.id and x.status='open') as open_reports
 from public.reviews r left join public.profiles p on p.id=r.user_id left join auth.users u on u.id=r.user_id order by r.created_at desc,r.id desc
 )t;return result;
end; $$;

create or replace function public.admin_moderate_review(target_id uuid,operation text,reason text,note text,featured boolean)
returns void language plpgsql security definer set search_path=public as $$ declare previous record;reason_label text;begin
 if not public.is_admin() then raise exception 'Admin required' using errcode='42501';end if;
 if operation is null or operation not in ('hidden','removed','restore','feature','note') or note is null or char_length(note)>1000 or featured is null then raise exception 'Invalid action';end if;
 if operation in ('hidden','removed') and (reason is null or reason not in ('spam','sara','lainnya') or char_length(btrim(note))<3) then raise exception 'Reason required';end if;
 select id,status,is_featured,admin_note into previous from public.reviews where id=target_id for update;
 if previous.id is null then raise exception 'Review missing';end if;
 if operation in ('hidden','removed') then
 reason_label:=case reason when 'spam' then 'Spam' when 'sara' then 'SARA' else 'Lainnya' end;
 update public.reviews set status=operation,is_featured=false,admin_note=reason_label||': '||btrim(note) where id=target_id;
 elsif operation='restore' then update public.reviews set status='published',admin_note=null where id=target_id;
 elsif operation='feature' then
 if previous.status is distinct from 'published' then raise exception 'Only published reviews can be featured';end if;
 update public.reviews set is_featured=featured where id=target_id;
 else
 if previous.status in ('hidden','removed') and char_length(btrim(note))<3 then raise exception 'Keep the takedown reason';end if;
 update public.reviews set admin_note=nullif(btrim(note),'') where id=target_id;
 end if;
 if operation in ('hidden','removed','restore') then update public.reports set status='handled',handled_by=auth.uid(),handled_at=now() where target_type='review' and reports.target_id=admin_moderate_review.target_id and status='open';end if;
 perform public.record_admin_audit('moderation.review.'||operation,target_id::text,jsonb_build_object('before',to_jsonb(previous),'reason',reason,'note',note,'featured',featured));
end; $$;

-- Only this private function resolves an anonymous content target to its author.
create or replace function public.moderation_target_author(target_kind text,target_id uuid)
returns uuid language plpgsql security definer set search_path=public as $$ declare owner_id uuid;begin
 if target_kind='story' then select author_id into owner_id from public.stories where id=target_id;
 elsif target_kind='comment' then select author_id into owner_id from public.story_comments where id=target_id;
 else raise exception 'Invalid target';end if;
 if owner_id is null then raise exception 'Content missing';end if;return owner_id;
end; $$;
revoke all on function public.moderation_target_author(text,uuid) from public,anon,authenticated;

create or replace function public.admin_story_queue()
returns jsonb language plpgsql security definer set search_path=public as $$ declare result jsonb;begin
 if not public.is_admin() then raise exception 'Admin required' using errcode='42501';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'kind',t.kind,'alias',t.alias,'body',t.body,'status',t.status,'needs_moderation',t.needs_moderation,
 'report_count',stats.report_count,'open_reports',stats.open_reports,'repeat_reporters',repeaters.n,'suspended',p.suspended_at is not null,'reports',stats.details) order by stats.open_reports desc,t.created_at desc),'[]'::jsonb) into result
 from (select id,'story'::text as kind,alias,body,status,needs_moderation,author_id,created_at from public.stories
 union all select id,'comment',alias,body,status,needs_moderation,author_id,created_at from public.story_comments)t
 left join public.profiles p on p.id=t.author_id
 cross join lateral(select count(*) as report_count,count(*) filter(where x.status='open') as open_reports,
 coalesce(jsonb_agg(jsonb_build_object('reason',x.reason,'detail',x.detail,'status',x.status) order by x.created_at desc),'[]'::jsonb) as details
 from public.reports x where x.target_type=t.kind and x.target_id=t.id)stats
 cross join lateral(select count(distinct x.reporter_id) as n from public.reports x
 left join public.stories s on x.target_type='story' and s.id=x.target_id
 left join public.story_comments c on x.target_type='comment' and c.id=x.target_id
 where coalesce(s.author_id,c.author_id)=t.author_id and x.reporter_id<>t.author_id and x.status<>'dismissed')repeaters
 where stats.report_count>0 or t.needs_moderation;
 return result;
end; $$;

create or replace function public.admin_moderate_story(target_kind text,target_id uuid,operation text,note text)
returns void language plpgsql security definer set search_path=public as $$ declare owner_id uuid;previous text;begin
 if not public.is_admin() then raise exception 'Admin required' using errcode='42501';end if;
 if target_kind is null or target_kind not in ('story','comment') or operation is null or operation not in ('hidden','removed','dismiss','suspend') or note is null or char_length(btrim(note)) not between 3 and 1000 then raise exception 'Invalid action';end if;
 if target_kind='story' then select status into previous from public.stories where id=target_id for update;
 else select status into previous from public.story_comments where id=target_id for update;end if;
 owner_id:=public.moderation_target_author(target_kind,target_id);
 if operation='suspend' then
 perform 1 from public.profiles where id=owner_id and role<>'admin' for update;
 if not found then raise exception 'Cannot suspend admins';end if;
 update public.profiles set suspended_at=coalesce(suspended_at,now()),suspension_reason=btrim(note) where id=owner_id;
 elsif operation in ('hidden','removed') then
 if target_kind='story' then update public.stories set status=operation,needs_moderation=false,admin_note=btrim(note) where id=target_id;
 else update public.story_comments set status=operation,needs_moderation=false,admin_note=btrim(note) where id=target_id;end if;
 else
 -- Dismissing a false positive releases automatically-held content, never a takedown.
 if target_kind='story' then update public.stories set status=case when needs_moderation and admin_note is null and status='hidden' then 'published' else status end,needs_moderation=false where id=target_id;
 else update public.story_comments set status=case when needs_moderation and admin_note is null and status='hidden' then 'published' else status end,needs_moderation=false where id=target_id;end if;
 end if;
 if operation<>'suspend' then update public.reports set status=case when operation='dismiss' then 'dismissed' else 'handled' end,handled_by=auth.uid(),handled_at=now() where reports.target_type=target_kind and reports.target_id=admin_moderate_story.target_id and status='open';end if;
 -- The audit target is content, not the hidden author ID.
 perform public.record_admin_audit('moderation.'||target_kind||'.'||operation,target_id::text,jsonb_build_object('before_status',previous,'note',note));
end; $$;

create or replace function public.admin_reveal_story_identity(target_kind text,target_id uuid,justification text,serious_case boolean)
returns jsonb language plpgsql security definer set search_path=public as $$ declare owner_id uuid;identity jsonb;begin
 if not public.is_admin() then raise exception 'Admin required' using errcode='42501';end if;
 if target_kind is null or target_kind not in ('story','comment') or serious_case is distinct from true or justification is null or char_length(btrim(justification)) not between 10 and 1000 then raise exception 'Justification required';end if;
 owner_id:=public.moderation_target_author(target_kind,target_id);
 select jsonb_build_object('name',coalesce(p.display_name,'Teman CeritaKita'),'email',coalesce(u.email,'Akun dihapus')) into identity from public.profiles p left join auth.users u on u.id=p.id where p.id=owner_id;
 perform public.record_admin_audit('moderation.identity.reveal',target_kind||':'||target_id::text,jsonb_build_object('justification',btrim(justification),'serious_case',serious_case));
 return identity;
end; $$;
revoke all on function public.admin_review_list(),public.admin_moderate_review(uuid,text,text,text,boolean),public.admin_story_queue(),public.admin_moderate_story(text,uuid,text,text),public.admin_reveal_story_identity(text,uuid,text,boolean) from public,anon;
grant execute on function public.admin_review_list(),public.admin_moderate_review(uuid,text,text,text,boolean),public.admin_story_queue(),public.admin_moderate_story(text,uuid,text,text),public.admin_reveal_story_identity(text,uuid,text,boolean) to authenticated;
commit;

-- 0014_pages_cms.sql
begin;
create table if not exists public.pages (
 id uuid primary key default gen_random_uuid(),slug text not null unique,title text not null,
 status text not null default 'draft' check(status in ('draft','published')),
 blocks jsonb not null default '[]',published_blocks jsonb,published_title text,
 has_draft boolean not null default true,updated_at timestamptz not null default now()
);
alter table public.pages add column if not exists published_blocks jsonb;
alter table public.pages add column if not exists published_title text;
alter table public.pages add column if not exists has_draft boolean not null default true;
update public.pages set published_blocks=blocks,published_title=title,has_draft=false where status='published' and published_blocks is null;
alter table public.pages enable row level security;
revoke all on public.pages from public,anon,authenticated;
grant select on public.pages to authenticated;
-- Draft blocks must never be exposed by an older broad read policy.
do $$ declare page_policy text;begin
 for page_policy in select policyname from pg_policies where schemaname='public' and tablename='pages' loop
 execute format('drop policy if exists %I on public.pages',page_policy);
 end loop;
end; $$;
create policy pages_admin_read on public.pages for select to authenticated using(public.is_admin());
create or replace view public.page_feed with(security_barrier=true) as
 select id,slug,coalesce(published_title,title) as title,coalesce(published_blocks,'[]'::jsonb) as blocks
 from public.pages where status='published';
revoke all on public.page_feed from public,anon,authenticated;
grant select on public.page_feed to anon,authenticated;

create or replace function public.admin_save_page(page_id uuid,page_title text,page_slug text,page_blocks jsonb,publish_now boolean)
returns uuid language plpgsql security definer set search_path=public as $$
declare target uuid;previous record;block jsonb;image_url text;types text[]:=array['hero','features','gallery','video','text','pricing','testimonials','chips','cta','faq','sponsor'];
begin
 if not public.is_admin() then raise exception 'Admin required' using errcode='42501';end if;
 if char_length(btrim(coalesce(page_title,''))) not between 1 and 200 or page_slug is null or publish_now is null
 or (page_slug<>'/' and (page_slug!~'^[a-z0-9]+(-[a-z0-9]+)*$' or char_length(page_slug)>180 or page_slug=any(array['admin','app','auth','masuk','kontak','review','api','ditangguhkan','_next'])))
 or jsonb_typeof(page_blocks) is distinct from 'array' or octet_length(page_blocks::text)>250000 then raise exception 'Invalid page';end if;
 if jsonb_array_length(page_blocks)>40 then raise exception 'Too many blocks';end if;
 for block in select value from jsonb_array_elements(page_blocks) loop
 if jsonb_typeof(block) is distinct from 'object' or coalesce(block->>'type','')<>all(types) or char_length(coalesce(block->>'id','')) not between 1 and 80 or jsonb_typeof(block->'items') is distinct from 'array' then raise exception 'Invalid block';end if;
 if jsonb_array_length(block->'items')>30 then raise exception 'Too many block items';end if;
 end loop;
 if (select count(distinct value->>'id') from jsonb_array_elements(page_blocks))<>jsonb_array_length(page_blocks) then raise exception 'Duplicate block IDs';end if;
 perform pg_advisory_xact_lock(hashtext('ceritakita-media-references'));
 for image_url in select value #>> '{}' from (
 select value from jsonb_path_query(page_blocks,'$[*].imageUrl') as q(value)
 union all select value from jsonb_path_query(page_blocks,'$[*].secondaryImageUrl') as q(value)
 union all select value from jsonb_path_query(page_blocks,'$[*].items[*].imageUrl') as q(value)
 )images loop
 if image_url<>'' and image_url<>all(array['/images/laptop.jpg','/images/meditasi.jpg','/logo-mark.png']) and not exists(select 1 from public.media where url=image_url and not deleting) then raise exception 'Pick media from the library';end if;
 end loop;
 target:=coalesce(page_id,gen_random_uuid());
 select id,slug,status,has_draft into previous from public.pages where id=target for update;
 if page_id is not null and previous.id is null then raise exception 'Page missing';end if;
 if previous.id is not null and previous.slug<>page_slug then raise exception 'Published page slug is immutable';end if;
 if page_slug='/' and previous.id is null then raise exception 'Homepage already seeded';end if;
 insert into public.pages(id,slug,title,status,blocks,published_blocks,published_title,has_draft,updated_at)
 values(target,page_slug,btrim(page_title),case when publish_now then 'published' else 'draft' end,page_blocks,case when publish_now then page_blocks else null end,case when publish_now then btrim(page_title) else null end,not publish_now,now())
 on conflict(id) do update set title=excluded.title,blocks=excluded.blocks,
 status=case when publish_now then 'published' else pages.status end,
 published_blocks=case when publish_now then excluded.blocks else pages.published_blocks end,
 published_title=case when publish_now then excluded.title else pages.published_title end,
 has_draft=not publish_now,updated_at=now();
 perform public.record_admin_audit(case when publish_now then 'cms.publish' else 'cms.draft.save' end,page_slug,jsonb_build_object('page_id',target,'block_count',jsonb_array_length(page_blocks),'before',to_jsonb(previous)));
 return target;
end; $$;
revoke all on function public.admin_save_page(uuid,text,text,jsonb,boolean) from public,anon;
grant execute on function public.admin_save_page(uuid,text,text,jsonb,boolean) to authenticated;

insert into public.pages(slug,title,status,blocks,published_blocks,published_title,has_draft) values('/', 'Beranda','published', $cmsseed$[
  {
    "id": "home-hero",
    "type": "hero",
    "title": "Tempat aman untuk semua ceritamu.",
    "eyebrow": "RUANG UNTUK MENJADI DIRIMU",
    "text": "",
    "buttonText": "Mulai Bercerita",
    "buttonHref": "/masuk",
    "imageUrl": "/images/meditasi.jpg",
    "imageAlt": "Perempuan menikmati waktu tenang di antara tanaman",
    "secondaryImageUrl": "/images/laptop.jpg",
    "visualLabel": "BERCERITA · BERTUMBUH · BERSAMA",
    "aboutTitle": "Setiap rasa punya cerita.",
    "aboutText": "Kadang, kita hanya butuh tempat untuk didengar. Mulai dari apa pun yang sedang kamu rasakan.",
    "aboutLabel": "Tentang {{site}}",
    "aboutButtonText": "Kenali {{site}}",
    "aboutButtonHref": "#fitur",
    "youtubeUrl": "",
    "html": "",
    "items": [],
    "useSiteChips": false
  },
  {
    "id": "home-features",
    "type": "features",
    "title": "",
    "eyebrow": "",
    "text": "",
    "buttonText": "",
    "buttonHref": "/masuk",
    "imageUrl": "",
    "imageAlt": "",
    "secondaryImageUrl": "",
    "visualLabel": "",
    "aboutTitle": "",
    "aboutText": "",
    "aboutLabel": "",
    "aboutButtonText": "",
    "aboutButtonHref": "#fitur",
    "youtubeUrl": "",
    "html": "",
    "items": [
      {
        "title": "Ruang Cerita Anonim",
        "text": "Ada ruang untuk setiap rasa. Ceritakan tanpa takut dihakimi.",
        "label": "Ceritamu berarti",
        "symbol": "♡",
        "imageUrl": "",
        "imageAlt": "",
        "href": "/masuk"
      },
      {
        "title": "Mood Tracker",
        "text": "Kenali perasaanmu, satu hari kecil dalam satu waktu.",
        "label": "Apa kabarmu?",
        "symbol": "☀",
        "imageUrl": "",
        "imageAlt": "",
        "href": "/masuk"
      },
      {
        "title": "Journaling",
        "text": "Tuangkan isi kepala. Temukan ruang tenang untuk dirimu.",
        "label": "Catatan untuk diri",
        "symbol": "✎",
        "imageUrl": "",
        "imageAlt": "",
        "href": "/masuk"
      },
      {
        "title": "Konten Edukasi",
        "text": "Belajar memahami diri lewat bacaan dan video ringan.",
        "label": "Tumbuh bersama",
        "symbol": "✿",
        "imageUrl": "",
        "imageAlt": "",
        "href": "/masuk"
      }
    ],
    "useSiteChips": false
  },
  {
    "id": "home-pricing",
    "type": "pricing",
    "title": "Ruang tumbuh untuk setiap cerita",
    "eyebrow": "SESUAI LANGKAHMU",
    "text": "",
    "buttonText": "",
    "buttonHref": "/masuk",
    "imageUrl": "",
    "imageAlt": "",
    "secondaryImageUrl": "",
    "visualLabel": "",
    "aboutTitle": "",
    "aboutText": "",
    "aboutLabel": "",
    "aboutButtonText": "",
    "aboutButtonHref": "#fitur",
    "youtubeUrl": "",
    "html": "",
    "items": [],
    "useSiteChips": false
  },
  {
    "id": "home-testimonials",
    "type": "testimonials",
    "title": "Apa kata mereka",
    "eyebrow": "CERITA DARI TEMAN KITA",
    "text": "Setiap perjalanan berbeda. Kamu boleh berjalan dengan ritmemu sendiri.",
    "buttonText": "",
    "buttonHref": "/masuk",
    "imageUrl": "",
    "imageAlt": "",
    "secondaryImageUrl": "",
    "visualLabel": "",
    "aboutTitle": "",
    "aboutText": "",
    "aboutLabel": "",
    "aboutButtonText": "",
    "aboutButtonHref": "#fitur",
    "youtubeUrl": "",
    "html": "",
    "items": [],
    "useSiteChips": false
  },
  {
    "id": "home-chips",
    "type": "chips",
    "title": "Bergabung dengan gerakan",
    "eyebrow": "",
    "text": "Langkah kecilmu berarti. Mari tumbuh bersama.",
    "buttonText": "",
    "buttonHref": "/masuk",
    "imageUrl": "",
    "imageAlt": "",
    "secondaryImageUrl": "",
    "visualLabel": "",
    "aboutTitle": "",
    "aboutText": "",
    "aboutLabel": "",
    "aboutButtonText": "",
    "aboutButtonHref": "#fitur",
    "youtubeUrl": "",
    "html": "",
    "items": [],
    "useSiteChips": true
  },
  {
    "id": "home-cta",
    "type": "cta",
    "title": "Siap mulai\n perjalananmu?",
    "eyebrow": "",
    "text": "Ada tempat untuk ceritamu di sini.",
    "buttonText": "Daftar Gratis",
    "buttonHref": "/masuk",
    "imageUrl": "",
    "imageAlt": "",
    "secondaryImageUrl": "",
    "visualLabel": "",
    "aboutTitle": "",
    "aboutText": "",
    "aboutLabel": "",
    "aboutButtonText": "",
    "aboutButtonHref": "#fitur",
    "youtubeUrl": "",
    "html": "",
    "items": [],
    "useSiteChips": false
  }
]$cmsseed$::jsonb,$cmsseed$[
  {
    "id": "home-hero",
    "type": "hero",
    "title": "Tempat aman untuk semua ceritamu.",
    "eyebrow": "RUANG UNTUK MENJADI DIRIMU",
    "text": "",
    "buttonText": "Mulai Bercerita",
    "buttonHref": "/masuk",
    "imageUrl": "/images/meditasi.jpg",
    "imageAlt": "Perempuan menikmati waktu tenang di antara tanaman",
    "secondaryImageUrl": "/images/laptop.jpg",
    "visualLabel": "BERCERITA · BERTUMBUH · BERSAMA",
    "aboutTitle": "Setiap rasa punya cerita.",
    "aboutText": "Kadang, kita hanya butuh tempat untuk didengar. Mulai dari apa pun yang sedang kamu rasakan.",
    "aboutLabel": "Tentang {{site}}",
    "aboutButtonText": "Kenali {{site}}",
    "aboutButtonHref": "#fitur",
    "youtubeUrl": "",
    "html": "",
    "items": [],
    "useSiteChips": false
  },
  {
    "id": "home-features",
    "type": "features",
    "title": "",
    "eyebrow": "",
    "text": "",
    "buttonText": "",
    "buttonHref": "/masuk",
    "imageUrl": "",
    "imageAlt": "",
    "secondaryImageUrl": "",
    "visualLabel": "",
    "aboutTitle": "",
    "aboutText": "",
    "aboutLabel": "",
    "aboutButtonText": "",
    "aboutButtonHref": "#fitur",
    "youtubeUrl": "",
    "html": "",
    "items": [
      {
        "title": "Ruang Cerita Anonim",
        "text": "Ada ruang untuk setiap rasa. Ceritakan tanpa takut dihakimi.",
        "label": "Ceritamu berarti",
        "symbol": "♡",
        "imageUrl": "",
        "imageAlt": "",
        "href": "/masuk"
      },
      {
        "title": "Mood Tracker",
        "text": "Kenali perasaanmu, satu hari kecil dalam satu waktu.",
        "label": "Apa kabarmu?",
        "symbol": "☀",
        "imageUrl": "",
        "imageAlt": "",
        "href": "/masuk"
      },
      {
        "title": "Journaling",
        "text": "Tuangkan isi kepala. Temukan ruang tenang untuk dirimu.",
        "label": "Catatan untuk diri",
        "symbol": "✎",
        "imageUrl": "",
        "imageAlt": "",
        "href": "/masuk"
      },
      {
        "title": "Konten Edukasi",
        "text": "Belajar memahami diri lewat bacaan dan video ringan.",
        "label": "Tumbuh bersama",
        "symbol": "✿",
        "imageUrl": "",
        "imageAlt": "",
        "href": "/masuk"
      }
    ],
    "useSiteChips": false
  },
  {
    "id": "home-pricing",
    "type": "pricing",
    "title": "Ruang tumbuh untuk setiap cerita",
    "eyebrow": "SESUAI LANGKAHMU",
    "text": "",
    "buttonText": "",
    "buttonHref": "/masuk",
    "imageUrl": "",
    "imageAlt": "",
    "secondaryImageUrl": "",
    "visualLabel": "",
    "aboutTitle": "",
    "aboutText": "",
    "aboutLabel": "",
    "aboutButtonText": "",
    "aboutButtonHref": "#fitur",
    "youtubeUrl": "",
    "html": "",
    "items": [],
    "useSiteChips": false
  },
  {
    "id": "home-testimonials",
    "type": "testimonials",
    "title": "Apa kata mereka",
    "eyebrow": "CERITA DARI TEMAN KITA",
    "text": "Setiap perjalanan berbeda. Kamu boleh berjalan dengan ritmemu sendiri.",
    "buttonText": "",
    "buttonHref": "/masuk",
    "imageUrl": "",
    "imageAlt": "",
    "secondaryImageUrl": "",
    "visualLabel": "",
    "aboutTitle": "",
    "aboutText": "",
    "aboutLabel": "",
    "aboutButtonText": "",
    "aboutButtonHref": "#fitur",
    "youtubeUrl": "",
    "html": "",
    "items": [],
    "useSiteChips": false
  },
  {
    "id": "home-chips",
    "type": "chips",
    "title": "Bergabung dengan gerakan",
    "eyebrow": "",
    "text": "Langkah kecilmu berarti. Mari tumbuh bersama.",
    "buttonText": "",
    "buttonHref": "/masuk",
    "imageUrl": "",
    "imageAlt": "",
    "secondaryImageUrl": "",
    "visualLabel": "",
    "aboutTitle": "",
    "aboutText": "",
    "aboutLabel": "",
    "aboutButtonText": "",
    "aboutButtonHref": "#fitur",
    "youtubeUrl": "",
    "html": "",
    "items": [],
    "useSiteChips": true
  },
  {
    "id": "home-cta",
    "type": "cta",
    "title": "Siap mulai\n perjalananmu?",
    "eyebrow": "",
    "text": "Ada tempat untuk ceritamu di sini.",
    "buttonText": "Daftar Gratis",
    "buttonHref": "/masuk",
    "imageUrl": "",
    "imageAlt": "",
    "secondaryImageUrl": "",
    "visualLabel": "",
    "aboutTitle": "",
    "aboutText": "",
    "aboutLabel": "",
    "aboutButtonText": "",
    "aboutButtonHref": "#fitur",
    "youtubeUrl": "",
    "html": "",
    "items": [],
    "useSiteChips": false
  }
]$cmsseed$::jsonb,'Beranda',false) on conflict(slug) do nothing;
commit;

begin;
create table if not exists public.seo_settings(id integer primary key default 1 check(id=1),settings jsonb not null default '{}',updated_at timestamptz not null default now());
create table if not exists public.seo_documents(path text primary key,meta jsonb not null default '{}',updated_at timestamptz not null default now());
create table if not exists public.seo_redirects(id uuid primary key default gen_random_uuid(),source text not null unique,destination text not null,active boolean not null default true,updated_at timestamptz not null default now());
create table if not exists public.sponsors(id uuid primary key default gen_random_uuid(),name text not null,logo_url text not null default '',title text not null,description text not null default '',link_url text not null,placement text not null check(placement in ('landing','dashboard','artikel')),start_at timestamptz,end_at timestamptz,is_active boolean not null default false,clicks bigint not null default 0,impressions bigint not null default 0,updated_at timestamptz not null default now());
create table if not exists public.sponsor_events(sponsor_id uuid not null references public.sponsors(id) on delete cascade,visitor_hash text not null,event_kind text not null check(event_kind in ('click','impression')),event_day date not null default current_date,primary key(sponsor_id,visitor_hash,event_kind,event_day));
create index if not exists sponsor_events_day_idx on public.sponsor_events(event_day);
create index if not exists sponsors_placement_idx on public.sponsors(placement,is_active);
alter table public.seo_settings enable row level security;
alter table public.seo_documents enable row level security;
alter table public.seo_redirects enable row level security;
alter table public.sponsors enable row level security;
alter table public.sponsor_events enable row level security;
revoke all on public.seo_settings,public.seo_documents,public.seo_redirects,public.sponsors,public.sponsor_events from public,anon,authenticated;
grant select on public.seo_settings,public.seo_documents,public.seo_redirects to anon,authenticated;
grant select on public.sponsors to authenticated;
drop policy if exists seo_settings_public_read on public.seo_settings;
create policy seo_settings_public_read on public.seo_settings for select to anon,authenticated using(true);
drop policy if exists seo_documents_read on public.seo_documents;
drop policy if exists seo_redirects_read on public.seo_redirects;
create policy seo_redirects_read on public.seo_redirects for select to anon,authenticated using(active or public.is_admin());
drop policy if exists sponsors_admin_read on public.sponsors;
create policy sponsors_admin_read on public.sponsors for select to authenticated using(public.is_admin());
create or replace view public.sponsor_feed with(security_barrier=true) as
select id,name,logo_url,title,description,link_url,placement,start_at,end_at,is_active from public.sponsors where is_active and (start_at is null or start_at<=now()) and (end_at is null or end_at>now());
revoke all on public.sponsor_feed from public,anon,authenticated;
grant select on public.sponsor_feed to anon,authenticated;
-- Public teasers never reveal premium article bodies or premium video IDs.
create or replace view public.seo_articles with(security_barrier=true) as
select id,slug,title,excerpt,cover_url,category,is_premium,published_at,case when not is_premium or public.can_read_premium_education() then content else null end as content from public.articles where status='published' and published_at<=now();
create or replace view public.seo_videos with(security_barrier=true) as
select id,title,description,category,is_premium,published_at,case when not is_premium or public.can_read_premium_education() then youtube_id else null end as youtube_id from public.videos where status='published' and published_at<=now();
revoke all on public.seo_articles,public.seo_videos from public,anon,authenticated;
grant select on public.seo_articles,public.seo_videos to anon,authenticated;
create policy seo_documents_read on public.seo_documents for select to anon,authenticated using(public.is_admin() or path in ('/','/kontak','/review','/masuk') or exists(select 1 from public.page_feed p where '/'||p.slug=path) or exists(select 1 from public.seo_articles a where '/artikel/'||a.slug=path));
create or replace function public.admin_save_marketing(kind text,payload jsonb)
returns text language plpgsql security definer set search_path=public as $$
declare target uuid;path_value text;image_url text;before_value jsonb;source_value text;next_path text;visited text[];v jsonb;start_value timestamptz;end_value timestamptz;
begin
 if not public.is_admin() then raise exception 'Admin required' using errcode='42501';end if;
 if jsonb_typeof(payload) is distinct from 'object' or octet_length(payload::text)>30000 then raise exception 'Invalid payload';end if;
 perform pg_advisory_xact_lock(hashtextextended('ceritakita-media-references',0));
 if kind='seo_global' then
  if char_length(coalesce(payload->>'titleTemplate','')) not between 1 and 150 or position('%s' in payload->>'titleTemplate')=0 or char_length(coalesce(payload->>'description',''))>500 or char_length(coalesce(payload->>'robots',''))>10000
  or coalesce(payload->>'canonicalBase','')!~'^(|https://[^/?#[:space:]]+/?$)' or coalesce(payload->>'analyticsId','')!~'^(|G-[A-Z0-9]{4,30})$' or coalesce(payload->>'googleVerification','')!~'^[-a-zA-Z0-9_]{0,200}$' or coalesce(payload->>'bingVerification','')!~'^[-a-zA-Z0-9_]{0,200}$' then raise exception 'Invalid SEO';end if;
  image_url:=coalesce(payload->>'ogImage','');select settings into before_value from public.seo_settings where id=1;
  if image_url<>'' and not exists(select 1 from public.media where url=image_url and not deleting) then raise exception 'Pick media from library';end if;
  insert into public.seo_settings(id,settings) values(1,payload) on conflict(id) do update set settings=excluded.settings,updated_at=now();path_value:='global';
 elsif kind='seo_document' then
  path_value:=payload->>'path';v:=payload->'meta';
  if jsonb_typeof(v) is distinct from 'object' or jsonb_typeof(v->'noindex') is distinct from 'boolean' or char_length(coalesce(v->>'title',''))>200 or char_length(coalesce(v->>'description',''))>500 or char_length(coalesce(v->>'canonical',''))>2048 or coalesce(v->>'canonical','')!~'^(|https://[^[:space:]@]+)$' then raise exception 'Invalid metadata';end if;
  if not (path_value in ('/','/kontak','/review','/masuk') or exists(select 1 from public.pages where '/'||slug=path_value) or exists(select 1 from public.articles where '/artikel/'||slug=path_value)) then raise exception 'Unknown page';end if;
  image_url:=coalesce(v->>'ogImage','');if image_url<>'' and not exists(select 1 from public.media where url=image_url and not deleting) then raise exception 'Pick media from library';end if;
  select meta into before_value from public.seo_documents where path=path_value;
  insert into public.seo_documents(path,meta) values(path_value,v) on conflict(path) do update set meta=excluded.meta,updated_at=now();
 elsif kind='redirect' then
  perform pg_advisory_xact_lock(hashtextextended('ceritakita-seo-redirects',0));
  target:=coalesce(nullif(payload->>'id','')::uuid,gen_random_uuid());source_value:=payload->>'source';next_path:=payload->>'destination';
  if source_value is null or source_value!~'^/([a-z0-9-]+/)*[a-z0-9-]*$' or source_value='/' or source_value~'^/(app|admin|api|auth|masuk|sponsor)(/|$)' or char_length(source_value)>180 or next_path is null or char_length(next_path)>2048 or (next_path!~'^/([a-z0-9-]+/)*[a-z0-9-]*$' and next_path!~'^https://[^[:space:]@]+$') or next_path=source_value or jsonb_typeof(payload->'active') is distinct from 'boolean' then raise exception 'Invalid redirect';end if;
  visited:=array[source_value];if (payload->>'active')::boolean then
   loop
    if next_path=any(visited) then raise exception 'Redirect cycle';end if;
    visited:=array_append(visited,next_path);if array_length(visited,1)>50 then raise exception 'Redirect chain too long';end if;
    select destination into next_path from public.seo_redirects where source=next_path and active and id<>target;
    exit when next_path is null;
   end loop;
  end if;
  select to_jsonb(r) into before_value from public.seo_redirects r where id=target;
  insert into public.seo_redirects(id,source,destination,active) values(target,source_value,payload->>'destination',(payload->>'active')::boolean) on conflict(id) do update set source=excluded.source,destination=excluded.destination,active=excluded.active,updated_at=now();path_value:=source_value;
 elsif kind='redirect_delete' then
  target:=(payload->>'id')::uuid;select to_jsonb(r) into before_value from public.seo_redirects r where id=target;delete from public.seo_redirects where id=target;path_value:=target::text;
 elsif kind='sponsor' then
  target:=coalesce(nullif(payload->>'id','')::uuid,gen_random_uuid());start_value:=nullif(payload->>'start_at','')::timestamptz;end_value:=nullif(payload->>'end_at','')::timestamptz;
  if char_length(btrim(coalesce(payload->>'name',''))) not between 1 and 100 or char_length(btrim(coalesce(payload->>'title',''))) not between 1 and 200 or char_length(coalesce(payload->>'description',''))>2000 or coalesce(payload->>'link_url','')!~'^https://[^[:space:]@]+$' or char_length(payload->>'link_url')>2048 or coalesce(payload->>'placement','') not in ('landing','dashboard','artikel') or jsonb_typeof(payload->'is_active') is distinct from 'boolean' or (start_value is not null and end_value is not null and start_value>=end_value) then raise exception 'Invalid sponsor';end if;
  image_url:=coalesce(payload->>'logo_url','');if image_url<>'' and not exists(select 1 from public.media where url=image_url and not deleting) then raise exception 'Pick media from library';end if;
  select to_jsonb(s) into before_value from public.sponsors s where id=target;
  insert into public.sponsors(id,name,logo_url,title,description,link_url,placement,start_at,end_at,is_active) values(target,btrim(payload->>'name'),image_url,btrim(payload->>'title'),coalesce(payload->>'description',''),payload->>'link_url',payload->>'placement',start_value,end_value,(payload->>'is_active')::boolean)
  on conflict(id) do update set name=excluded.name,logo_url=excluded.logo_url,title=excluded.title,description=excluded.description,link_url=excluded.link_url,placement=excluded.placement,start_at=excluded.start_at,end_at=excluded.end_at,is_active=excluded.is_active,updated_at=now();path_value:=target::text;
 elsif kind='sponsor_delete' then
  target:=(payload->>'id')::uuid;select to_jsonb(s) into before_value from public.sponsors s where id=target;delete from public.sponsors where id=target;path_value:=target::text;
 else raise exception 'Unknown operation';end if;
 perform public.record_admin_audit(kind,path_value,jsonb_build_object('before',before_value,'after',payload));
 return coalesce(target::text,path_value);
end;$$;
revoke all on function public.admin_save_marketing(text,jsonb) from public,anon;
grant execute on function public.admin_save_marketing(text,jsonb) to authenticated;
create or replace function public.record_sponsor_event(sponsor_uuid uuid,visitor_hash_value text,event_type text,event_placement text)
returns boolean language plpgsql security definer set search_path=public as $$
declare inserted integer;
begin
 if visitor_hash_value is null or event_type is null or event_placement is null or visitor_hash_value!~'^[a-f0-9]{64}$' or event_type not in ('click','impression') or event_placement not in ('landing','dashboard','artikel') then return false;end if;
 perform pg_advisory_xact_lock(hashtextextended(visitor_hash_value,0));
 if not exists(select 1 from public.sponsors where id=sponsor_uuid and placement=event_placement and is_active and (start_at is null or start_at<=now()) and (end_at is null or end_at>now())) then return false;end if;
 if (select count(*) from public.sponsor_events where visitor_hash=visitor_hash_value and event_day=current_date)>=100 then return false;end if;
 insert into public.sponsor_events(sponsor_id,visitor_hash,event_kind) values(sponsor_uuid,visitor_hash_value,event_type) on conflict do nothing;
 get diagnostics inserted=row_count;
 if inserted>0 then update public.sponsors set clicks=clicks+case when event_type='click' then 1 else 0 end,impressions=impressions+case when event_type='impression' then 1 else 0 end where id=sponsor_uuid;end if;
 delete from public.sponsor_events where event_day<current_date-30;
 return inserted>0;
end;$$;
revoke all on function public.record_sponsor_event(uuid,text,text,text) from public;
grant execute on function public.record_sponsor_event(uuid,text,text,text) to anon,authenticated;
insert into public.seo_settings(id,settings) values(1,'{"titleTemplate":"%s | CeritaKita","description":"Tempat aman untuk bercerita, mencatat mood, menulis jurnal, dan belajar kesehatan mental.","ogImage":"","canonicalBase":"","googleVerification":"","bingVerification":"","analyticsId":"","robots":"User-agent: *\nAllow: /\nDisallow: /app\nDisallow: /admin\nDisallow: /auth\n"}') on conflict(id) do nothing;
commit;

begin;
alter table public.profiles add column if not exists suspended_at timestamptz;
alter table public.profiles add column if not exists suspension_reason text;
create index if not exists audit_logs_action_created_idx on public.audit_logs(action,created_at desc);
create index if not exists orders_paid_verified_idx on public.orders(verified_at) where status='paid';
-- These functions accept an actor only from a verified server session. API users cannot execute them.
create or replace function public.admin_user_list(actor uuid,search_value text default '',role_filter text default '',status_filter text default '',premium_filter text default '',page_number integer default 1,page_size integer default 20)
returns jsonb language plpgsql security definer set search_path=public as $$
declare rows_json jsonb;total_count bigint;
begin
 if not exists(select 1 from public.profiles where id=actor and role='admin' and suspended_at is null) then raise exception 'Admin required' using errcode='42501';end if;
 if search_value is null or char_length(search_value)>254 or role_filter is null or role_filter not in ('','user','editor','admin') or status_filter is null or status_filter not in ('','active','suspended') or premium_filter is null or premium_filter not in ('','premium','free') or page_number is null or page_number not between 1 and 100000 or page_size is null or page_size not between 1 and 100 then raise exception 'Invalid filter';end if;
 select count(*) into total_count from auth.users u left join public.profiles p on p.id=u.id where
 (strpos(lower(coalesce(u.email,'')||' '||coalesce(p.display_name,'')),lower(btrim(search_value)))>0)
 and (role_filter='' or coalesce(p.role,'user')=role_filter)
 and (status_filter='' or (status_filter='active' and p.suspended_at is null) or (status_filter='suspended' and p.suspended_at is not null))
 and (premium_filter='' or (premium_filter='premium' and p.premium_until>now()) or (premium_filter='free' and (p.premium_until is null or p.premium_until<=now())));
 select coalesce(jsonb_agg(to_jsonb(r)),'[]'::jsonb) into rows_json from (
 select u.id,coalesce(u.email,'Tanpa email') as email,coalesce(nullif(p.display_name,''),split_part(u.email,'@',1),'Teman CeritaKita') as name,coalesce(p.role,'user') as role,p.premium_until,u.created_at,p.suspended_at,p.suspension_reason
 from auth.users u left join public.profiles p on p.id=u.id where
 (strpos(lower(coalesce(u.email,'')||' '||coalesce(p.display_name,'')),lower(btrim(search_value)))>0)
 and (role_filter='' or coalesce(p.role,'user')=role_filter)
 and (status_filter='' or (status_filter='active' and p.suspended_at is null) or (status_filter='suspended' and p.suspended_at is not null))
 and (premium_filter='' or (premium_filter='premium' and p.premium_until>now()) or (premium_filter='free' and (p.premium_until is null or p.premium_until<=now())))
 order by u.created_at desc,u.id desc limit page_size offset (page_number-1)*page_size
 )r;
 return jsonb_build_object('rows',rows_json,'total',total_count);
end;$$;
create or replace function public.admin_change_user(actor uuid,target_user uuid,operation text,new_role text default 'user',active_until timestamptz default null,note text default '')
returns void language plpgsql security definer set search_path=public as $$
declare previous public.profiles%rowtype;next_value jsonb;
begin
 -- Serialize role changes so two admins cannot demote each other simultaneously.
 perform pg_advisory_xact_lock(hashtextextended('ceritakita-admin-users',0));
 if not exists(select 1 from public.profiles where id=actor and role='admin' and suspended_at is null) then raise exception 'Admin required' using errcode='42501';end if;
 if target_user is null or operation is null or operation not in ('role','premium_grant','premium_revoke','suspend','activate') or new_role is null or new_role not in ('user','editor','admin') or note is null or char_length(note)>1000 then raise exception 'Invalid operation';end if;
 if actor=target_user and operation='role' and new_role<>'admin' then raise exception 'Self demotion forbidden';end if;
 if actor=target_user and operation='suspend' then raise exception 'Self suspension forbidden';end if;
 if operation='premium_grant' and (active_until is null or active_until<=now()) then raise exception 'Future premium date required';end if;
 if operation='suspend' and char_length(btrim(note))<3 then raise exception 'Suspension reason required';end if;
 if not exists(select 1 from auth.users where id=target_user) then raise exception 'User missing';end if;
 insert into public.profiles(id,display_name) select id,split_part(email,'@',1) from auth.users where id=target_user on conflict(id) do nothing;
 select * into previous from public.profiles where id=target_user for update;
 if operation='role' then update public.profiles set role=new_role where id=target_user;
 elsif operation='premium_grant' then update public.profiles set premium_until=active_until where id=target_user;
 elsif operation='premium_revoke' then update public.profiles set premium_until=null where id=target_user;
 elsif operation='suspend' then update public.profiles set suspended_at=now(),suspension_reason=btrim(note) where id=target_user;
 else update public.profiles set suspended_at=null,suspension_reason=null where id=target_user;end if;
 select jsonb_build_object('role',role,'premium_until',premium_until,'suspended_at',suspended_at) into next_value from public.profiles where id=target_user;
 insert into public.audit_logs(actor_id,action,target,meta) values(actor,'user.'||operation,target_user::text,jsonb_build_object('before',jsonb_build_object('role',previous.role,'premium_until',previous.premium_until,'suspended_at',previous.suspended_at),'after',next_value,'note',btrim(note)));
end;$$;
create or replace function public.admin_audit_list(actor uuid,search_value text default '',action_filter text default '',start_date date default null,end_date date default null,page_number integer default 1,page_size integer default 20)
returns jsonb language plpgsql security definer set search_path=public as $$
declare rows_json jsonb;total_count bigint;actions_json jsonb;start_time timestamptz;end_time timestamptz;
begin
 if not exists(select 1 from public.profiles where id=actor and role='admin' and suspended_at is null) then raise exception 'Admin required' using errcode='42501';end if;
 if search_value is null or char_length(search_value)>254 or action_filter is null or char_length(action_filter)>100 or (start_date is not null and end_date is not null and start_date>end_date) or page_number is null or page_number not between 1 and 100000 or page_size is null or page_size not between 1 and 100 then raise exception 'Invalid filter';end if;
 start_time:=start_date::timestamp at time zone 'Asia/Jakarta';end_time:=(end_date+1)::timestamp at time zone 'Asia/Jakarta';
 select count(*) into total_count from public.audit_logs a left join public.profiles p on p.id=a.actor_id left join auth.users u on u.id=a.actor_id where
 (action_filter='' or a.action=action_filter) and (start_time is null or a.created_at>=start_time) and (end_time is null or a.created_at<end_time)
 and strpos(lower(coalesce(p.display_name,'')||' '||coalesce(u.email,'')||' '||a.action||' '||coalesce(a.target,'')),lower(btrim(search_value)))>0;
 select coalesce(jsonb_agg(to_jsonb(r)),'[]'::jsonb) into rows_json from (
 select a.id,a.created_at,coalesce(nullif(p.display_name,''),u.email,'Admin dihapus') as admin,coalesce(u.email,'') as email,a.action,a.target
 from public.audit_logs a left join public.profiles p on p.id=a.actor_id left join auth.users u on u.id=a.actor_id where
 (action_filter='' or a.action=action_filter) and (start_time is null or a.created_at>=start_time) and (end_time is null or a.created_at<end_time)
 and strpos(lower(coalesce(p.display_name,'')||' '||coalesce(u.email,'')||' '||a.action||' '||coalesce(a.target,'')),lower(btrim(search_value)))>0
 order by a.created_at desc,a.id desc limit page_size offset (page_number-1)*page_size
 )r;
 select coalesce(jsonb_agg(action),'[]'::jsonb) into actions_json from (select distinct action from public.audit_logs order by action limit 200)t;
 return jsonb_build_object('rows',rows_json,'total',total_count,'actions',actions_json);
end;$$;
create or replace function public.admin_dashboard_metrics(actor uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare today date:=(now() at time zone 'Asia/Jakarta')::date;month_start timestamptz;first_day timestamptz;days_json jsonb;
begin
 if not exists(select 1 from public.profiles where id=actor and role='admin' and suspended_at is null) then raise exception 'Admin required' using errcode='42501';end if;
 month_start:=date_trunc('month',now() at time zone 'Asia/Jakarta') at time zone 'Asia/Jakarta';first_day:=(today-29)::timestamp at time zone 'Asia/Jakarta';
 with registrations as(select (created_at at time zone 'Asia/Jakarta')::date as day,count(*) as value from auth.users where created_at>=first_day and created_at<=now() group by 1),
 revenue as(select (verified_at at time zone 'Asia/Jakarta')::date as day,sum(total_amount) as value from public.orders where status='paid' and verified_at>=first_day and verified_at<=now() group by 1)
 select jsonb_agg(jsonb_build_object('day',d.day::date,'registrations',coalesce(u.value,0),'revenue',coalesce(r.value,0)) order by d.day) into days_json from generate_series(today-29,today,interval '1 day') as d(day) left join registrations u on u.day=d.day::date left join revenue r on r.day=d.day::date;
 return jsonb_build_object(
 'new_users',(select count(*) from auth.users where created_at>=now()-interval '7 days' and created_at<=now()),
 'monthly_revenue',(select coalesce(sum(total_amount),0) from public.orders where status='paid' and verified_at>=month_start and verified_at<=now()),
 'awaiting_orders',(select count(*) from public.orders where status='awaiting_verification'),
 'open_reports',(select count(*) from public.reports where status='open'),
 'unknown_payment_dates',(select count(*) from public.orders where status='paid' and verified_at is null),
 'days',coalesce(days_json,'[]'::jsonb));
end;$$;
revoke all on function public.admin_user_list(uuid,text,text,text,text,integer,integer),public.admin_change_user(uuid,uuid,text,text,timestamptz,text),public.admin_audit_list(uuid,text,text,date,date,integer,integer),public.admin_dashboard_metrics(uuid) from public,anon,authenticated;
grant execute on function public.admin_user_list(uuid,text,text,text,text,integer,integer),public.admin_change_user(uuid,uuid,text,text,timestamptz,text),public.admin_audit_list(uuid,text,text,date,date,integer,integer),public.admin_dashboard_metrics(uuid) to service_role;
commit;

-- 0017_paid_plans_purchase_reviews.sql
begin;

-- Free is the account default, never a product checkout. Keep legacy rows/users.
update public.plans set is_active=false,is_highlighted=false where price_idr=0 or period='free';
alter table public.profiles alter column premium_until set default null;
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public as $$ begin
 insert into public.profiles(id,display_name,premium_until) values(new.id,split_part(new.email,'@',1),null) on conflict(id) do nothing;
 return new;
end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();
insert into public.profiles(id,display_name,premium_until) select id,split_part(email,'@',1),null from auth.users on conflict(id) do nothing;

create or replace function public.admin_save_plan(payload jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare plan_id uuid; feature_list text[]; old_plan jsonb;
begin
 if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
 if payload is null or jsonb_typeof(payload)<>'object' or octet_length(payload::text)>20000 then raise exception 'Paket tidak valid'; end if;
 if coalesce(length(trim(payload->>'name')),0) not between 1 and 80 or coalesce(payload->>'slug','') !~ '^[a-z0-9]+(-[a-z0-9]+)*$' or length(payload->>'slug')>80 then raise exception 'Paket tidak valid'; end if;
 if coalesce(payload->>'period','') not in ('monthly','yearly') or coalesce(payload->>'price_idr','') !~ '^[0-9]+$' or (payload->>'price_idr')::bigint>20000 then raise exception 'Harga tidak valid'; end if;
 if (payload->>'price_idr')::integer<9000 then raise exception 'Harga tidak valid'; end if;
 if jsonb_typeof(payload->'features') is distinct from 'array' or jsonb_array_length(payload->'features')>30 then raise exception 'Fitur tidak valid'; end if;
 if exists(select 1 from jsonb_array_elements(payload->'features') f where jsonb_typeof(f)<>'string' or length(trim(f#>>'{}')) not between 1 and 200) then raise exception 'Fitur tidak valid'; end if;
 select coalesce(array_agg(trim(f)),array[]::text[]) into feature_list from jsonb_array_elements_text(payload->'features') f;
 if jsonb_typeof(payload->'is_active') is distinct from 'boolean' or jsonb_typeof(payload->'is_highlighted') is distinct from 'boolean' or coalesce(payload->>'sort','') !~ '^[0-9]{1,4}$' then raise exception 'Status tidak valid'; end if;
 if nullif(payload->>'id','') is not null then
  plan_id:=(payload->>'id')::uuid;
  select to_jsonb(p) into old_plan from public.plans p where p.id=plan_id for update;
  if old_plan is null then raise exception 'Paket tidak ditemukan'; end if;
  update public.plans set name=trim(payload->>'name'),slug=payload->>'slug',price_idr=(payload->>'price_idr')::integer,period=payload->>'period',features=feature_list,is_active=(payload->>'is_active')::boolean,is_highlighted=(payload->>'is_highlighted')::boolean,sort=(payload->>'sort')::integer where id=plan_id;
 else
  insert into public.plans(name,slug,price_idr,period,features,is_active,is_highlighted,sort) values(trim(payload->>'name'),payload->>'slug',(payload->>'price_idr')::integer,payload->>'period',feature_list,(payload->>'is_active')::boolean,(payload->>'is_highlighted')::boolean,(payload->>'sort')::integer) returning id into plan_id;
 end if;
 perform public.record_admin_audit(case when old_plan is null then 'plan.create' else 'plan.update' end,plan_id::text,jsonb_build_object('before',old_plan,'after',payload));
 return plan_id;
end; $$;
create or replace function public.create_premium_order(selected_plan uuid)
returns uuid language plpgsql security definer set search_path = public
as $$
declare p record; settings record; code integer; order_id uuid; existing uuid; expiry integer;
begin
  if auth.uid() is null then raise exception 'Masuk terlebih dahulu'; end if;
  perform pg_advisory_xact_lock(hashtextextended('ceritakita-payment-orders',0));
  perform public.expire_my_orders();
  select id,name,slug,price_idr,period,features,is_active into p from public.plans where id=selected_plan and is_active for share;
  if p.id is null or p.period not in ('monthly','yearly') or p.price_idr is null or p.price_idr<9000 or p.price_idr>20000 then raise exception 'Paket tidak tersedia'; end if;

  select id into existing from public.orders where user_id=auth.uid() and plan_id=selected_plan and status in ('pending','rejected') and expires_at>now() order by created_at desc limit 1;
  if existing is not null then return existing; end if;
  if exists(select 1 from public.orders where user_id=auth.uid() and status in ('pending','awaiting_verification','rejected')) then raise exception 'Selesaikan pesanan sebelumnya dulu, ya.'; end if;
  if (select count(*) from public.orders where user_id=auth.uid() and created_at>now()-interval '1 day') >= 5 then raise exception 'Maksimal 5 pesanan per hari.'; end if;
  select id,qris_image_url,merchant_name,instructions,expiry_minutes,unique_code_enabled,provider_label into settings from public.payment_settings where id=1 for share;
  if settings.qris_image_url is null or settings.qris_image_url !~ '^https://' then raise exception 'QRIS belum tersedia'; end if;
  expiry := greatest(1,least(coalesce(settings.expiry_minutes,60),1440));
  code := 0;
  if settings.unique_code_enabled then
    select candidate into code from generate_series(1,99) candidate
    where not exists(select 1 from public.orders where total_amount=p.price_idr+candidate and status in ('pending','awaiting_verification','rejected'))
    order by random() limit 1;
    if code is null then raise exception 'Kode pembayaran sedang penuh. Coba lagi nanti.'; end if;
  end if;
  insert into public.profiles(id,display_name) select auth.uid(),split_part(email,'@',1) from auth.users where id=auth.uid() on conflict(id) do nothing;
  insert into public.orders(user_id,plan_id,base_amount,unique_code,total_amount,status,expires_at,qris_image_url,merchant_name,instructions)
  values(auth.uid(),p.id,p.price_idr,code,p.price_idr+code,'pending',now()+make_interval(mins=>expiry),settings.qris_image_url,settings.merchant_name,settings.instructions)
  returning id into order_id;
  return order_id;
end; $$;
revoke all on function public.create_premium_order(uuid) from public;
grant execute on function public.create_premium_order(uuid) to authenticated;

-- Admin REST writes cannot create or reactivate a free product either.
create or replace function public.guard_paid_plan()
returns trigger language plpgsql security definer set search_path=public as $$ begin
 if new.price_idr is null or new.price_idr<=0 or new.period is null or new.period not in ('monthly','yearly') then
  if tg_op='UPDATE' and (old.price_idr=0 or old.period='free') and new.price_idr is not distinct from old.price_idr and new.period is not distinct from old.period and new.is_active is false then return new;end if;
  raise exception 'Paket Gratis adalah status akun, bukan produk yang dapat dibeli';
 end if;
 return new;
end; $$;
drop trigger if exists guard_paid_plan on public.plans;
create trigger guard_paid_plan before insert or update of price_idr,period,is_active on public.plans for each row execute function public.guard_paid_plan();
revoke all on function public.guard_paid_plan() from public,anon,authenticated;

-- Defense in depth for service-side inserts as well as RPC checkout.
create or replace function public.guard_paid_order()
returns trigger language plpgsql security definer set search_path=public as $$ begin
 if new.base_amount is null or new.base_amount<=0 or new.total_amount is null or new.total_amount<=0
 or not exists(select 1 from public.plans where id=new.plan_id and price_idr>0 and period in ('monthly','yearly')) then raise exception 'Paket gratis tidak dapat dibeli';end if;
 return new;
end; $$;
drop trigger if exists guard_paid_order on public.orders;
create trigger guard_paid_order before insert or update of plan_id,base_amount,total_amount on public.orders for each row execute function public.guard_paid_order();

-- Reject verification of legacy zero-price orders as well.
create or replace function public.admin_verify_payment(actor uuid,order_id uuid,decision text,rejection_reason text default '')
returns jsonb language plpgsql security definer set search_path=public as $$
declare payment public.orders%rowtype;active_until timestamptz;next_until timestamptz;minutes integer;
begin
 if not exists(select 1 from public.profiles where id=actor and role='admin') then raise exception 'Admin required' using errcode='42501';end if;
 if decision is null or decision not in ('paid','rejected') or rejection_reason is null or char_length(rejection_reason)>1000 or (decision='rejected' and btrim(rejection_reason)='') then raise exception 'Invalid decision';end if;
 select * into payment from public.orders where id=order_id for update;
 if payment.id is null or payment.status is distinct from 'awaiting_verification' or payment.proof_url is null
 or payment.proof_url not like payment.user_id::text||'/'||payment.id::text||'/%'
 or not exists(select 1 from storage.objects where bucket_id='proofs' and name=payment.proof_url) then raise exception 'Order is not awaiting verification';end if;
 if decision='paid' then
  if coalesce(payment.base_amount,0)<=0 or coalesce(payment.total_amount,0)<=0 or payment.plan_period is null or payment.plan_period not in ('monthly','yearly') then raise exception 'Invalid paid plan period';end if;
  select premium_until into active_until from public.profiles where id=payment.user_id for update;
  if not found then raise exception 'Profile not found';end if;
  next_until:=greatest(coalesce(active_until,now()),now())+case when payment.plan_period='yearly' then interval '1 year' else interval '1 month' end;
  update public.profiles set premium_until=next_until where id=payment.user_id;
  update public.orders set status='paid',note=null,verified_by=actor,verified_at=now() where id=payment.id;
 else
  select greatest(1,least(coalesce(expiry_minutes,60),1440)) into minutes from public.payment_settings where id=1;
  update public.orders set status='rejected',note=btrim(rejection_reason),verified_by=actor,verified_at=now(),expires_at=greatest(expires_at,now()+make_interval(mins=>coalesce(minutes,60))) where id=payment.id;
 end if;
 insert into public.audit_logs(actor_id,action,target,meta) values(actor,'payment.'||decision,payment.id::text,jsonb_build_object('before_status',payment.status,'reason',case when decision='rejected' then btrim(rejection_reason) else null end,'premium_until',next_until));
 return jsonb_build_object('user_id',payment.user_id,'plan_name',payment.plan_name,'premium_until',next_until);
end; $$;

-- Preserve legacy reviews as a private archive; do not invent a purchase for them.
drop trigger if exists guard_review_write on public.reviews;
alter table public.reviews add column if not exists order_id uuid;
alter table public.reviews add column if not exists plan_id uuid;
alter table public.reviews add column if not exists comment text;
alter table public.reviews add column if not exists display_name text;
alter table public.reviews add column if not exists updated_at timestamptz;
alter table public.reviews drop constraint if exists reviews_user_id_key;
alter table public.reviews drop constraint if exists reviews_order_id_fkey;
alter table public.reviews add constraint reviews_order_id_fkey foreign key(order_id) references public.orders(id) on delete cascade;
alter table public.reviews drop constraint if exists reviews_plan_id_fkey;
alter table public.reviews add constraint reviews_plan_id_fkey foreign key(plan_id) references public.plans(id);
create unique index if not exists reviews_order_id_unique on public.reviews(order_id);
alter table public.reviews drop constraint if exists reviews_status_check;
update public.reviews set comment=coalesce(comment,body,''),display_name=coalesce(nullif(display_name,''),'Teman '||substr(id::text,1,6)),updated_at=coalesce(updated_at,created_at,now());
update public.reviews set status='hidden',is_featured=false where order_id is null or status is null or status not in ('pending','approved','hidden');
alter table public.reviews alter column comment set not null;
alter table public.reviews alter column display_name set not null;
alter table public.reviews alter column updated_at set default now();
alter table public.reviews alter column updated_at set not null;
alter table public.reviews alter column status set default 'pending';
alter table public.reviews alter column status set not null;
alter table public.reviews add constraint reviews_status_check check(status in ('pending','approved','hidden'));
create index if not exists reviews_user_order_idx on public.reviews(user_id,order_id);

-- A persistent, transaction-safe limit across server instances. No client access.
create table if not exists public.review_write_limits(user_id uuid primary key references public.profiles(id) on delete cascade,attempts timestamptz[] not null default '{}');
alter table public.review_write_limits enable row level security;
revoke all on public.review_write_limits from public,anon,authenticated;
create or replace function public.review_plain_text(value text)
returns text language sql immutable set search_path=public as $$
 select regexp_replace(replace(replace(regexp_replace(regexp_replace(regexp_replace(coalesce(value,''),'<(script|style)[^>]*>.*?</(script|style)[[:space:]]*>','','gis'),'<[^>]*>','','g'),'[^[:print:][:space:]]','','g'),chr(11),''),chr(12),''),'^[[:space:]]+|[[:space:]]+$','','g');
$$;
create or replace function public.guard_review_write()
returns trigger language plpgsql security definer set search_path=public as $$
declare purchase public.orders%rowtype; recent timestamptz[];content_changed boolean;
begin
 if tg_op='UPDATE' and (new.user_id is distinct from old.user_id or new.order_id is distinct from old.order_id or new.plan_id is distinct from old.plan_id or new.created_at is distinct from old.created_at) then raise exception 'Identitas pesanan tidak dapat diubah';end if;
 if tg_op='INSERT' then content_changed:=true;
 else content_changed:=new.rating is distinct from old.rating or new.comment is distinct from old.comment or new.display_name is distinct from old.display_name or new.body is distinct from old.body or new.title is distinct from old.title;end if;
 if content_changed then
  if auth.uid() is null or (new.user_id<>auth.uid() and not public.is_admin()) then raise exception 'Akses ditolak';end if;
  select * into purchase from public.orders where id=new.order_id for share;
  if purchase.id is null or purchase.user_id is distinct from new.user_id or purchase.status is distinct from 'paid' or coalesce(purchase.base_amount,0)<=0 or purchase.plan_id is null then raise exception 'Pesanan berbayar disetujui diperlukan';end if;
  new.comment:=public.review_plain_text(new.comment);new.display_name:=public.review_plain_text(new.display_name);
  if new.rating is null or new.rating not between 1 and 5 or char_length(new.comment) not between 10 and 500 or char_length(new.display_name) not between 1 and 60 then raise exception 'Ulasan tidak valid';end if;
  perform pg_advisory_xact_lock(hashtextextended('review-write:'||auth.uid()::text,0));
  select coalesce(array_agg(t),array[]::timestamptz[]) into recent from public.review_write_limits l cross join lateral unnest(l.attempts) t where l.user_id=auth.uid() and t>now()-interval '10 minutes';
  if cardinality(recent)>=5 then raise exception 'Batas ulasan tercapai';end if;
  insert into public.review_write_limits(user_id,attempts) values(auth.uid(),array_append(recent,now())) on conflict(user_id) do update set attempts=excluded.attempts;
  new.plan_id:=purchase.plan_id;new.body:=new.comment;new.title:='';new.is_featured:=false;
  if tg_op='UPDATE' and old.status='hidden' then new.status:='hidden';else new.status:='pending';end if;
  new.updated_at:=now();
 elsif tg_op='UPDATE' and (new.status is distinct from old.status or new.is_featured is distinct from old.is_featured or new.admin_note is distinct from old.admin_note) then
  if not public.is_admin() then raise exception 'Moderasi hanya oleh admin';end if;
  new.updated_at:=now();
 end if;
 return new;
end; $$;
create trigger guard_review_write before insert or update on public.reviews for each row execute function public.guard_review_write();
revoke all on function public.guard_review_write(),public.guard_paid_order(),public.handle_new_user() from public,anon,authenticated;

create or replace function public.review_is_published(target uuid)
returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.reviews r join public.orders o on o.id=r.order_id where r.id=target and r.status='approved' and o.status='paid' and o.base_amount>0 and o.user_id=r.user_id and o.plan_id=r.plan_id);
$$;
revoke all on function public.review_is_published(uuid) from public;
grant execute on function public.review_is_published(uuid) to anon,authenticated;
alter table public.reviews enable row level security;
do $$ declare pol record;begin
 for pol in select policyname from pg_policies where schemaname='public' and tablename='reviews' loop execute format('drop policy if exists %I on public.reviews',pol.policyname);end loop;
end; $$;
create policy reviews_public_approved on public.reviews for select to anon using(status='approved' and public.review_is_published(id));
create policy reviews_owner_read on public.reviews for select to authenticated using(user_id=auth.uid() or public.is_admin());
create policy reviews_owner_insert on public.reviews for insert to authenticated with check(user_id=auth.uid() and status='pending' and exists(select 1 from public.orders o where o.id=order_id and o.user_id=auth.uid() and o.status='paid' and o.base_amount>0 and o.plan_id=reviews.plan_id));
create policy reviews_owner_update on public.reviews for update to authenticated using(user_id=auth.uid() or public.is_admin()) with check(user_id=auth.uid() or public.is_admin());
create policy reviews_owner_delete on public.reviews for delete to authenticated using(user_id=auth.uid() or public.is_admin());
revoke all on public.reviews from public,anon,authenticated;
grant select(id,rating,comment,display_name,status,created_at,updated_at) on public.reviews to anon;
grant select,delete on public.reviews to authenticated;
grant insert(user_id,order_id,rating,comment,display_name) on public.reviews to authenticated;
grant update(rating,comment,display_name) on public.reviews to authenticated;

-- Deliberate owner-executed view: identity columns stay private even to logged-in readers.
create or replace view public.review_feed with(security_barrier=true) as
select r.id,r.display_name as name,r.rating,r.title,r.comment as body,r.photos,r.is_featured,r.helpful_count,
 (r.created_at at time zone 'Asia/Jakarta')::date as day,
 exists(select 1 from public.review_votes v where v.review_id=r.id and v.user_id=auth.uid()) as voted,
 r.created_at,coalesce(o.plan_name,p.name,'Paket') as plan_name
from public.reviews r join public.orders o on o.id=r.order_id left join public.plans p on p.id=r.plan_id
where r.status='approved' and r.rating between 1 and 5 and o.status='paid' and o.base_amount>0 and o.user_id=r.user_id and o.plan_id=r.plan_id
order by r.created_at desc,r.id desc;
revoke all on public.review_feed from public,anon,authenticated;
grant select on public.review_feed to anon,authenticated;
create or replace function public.public_review_summary()
returns jsonb language sql stable security definer set search_path=public as $$
 select jsonb_build_object('total',count(*),'average',coalesce(avg(rating),0),'distribution',jsonb_build_object('1',count(*) filter(where rating=1),'2',count(*) filter(where rating=2),'3',count(*) filter(where rating=3),'4',count(*) filter(where rating=4),'5',count(*) filter(where rating=5))) from public.review_feed;
$$;
revoke all on function public.public_review_summary() from public;
grant execute on function public.public_review_summary() to anon,authenticated;

create or replace function public.admin_review_list()
returns jsonb language plpgsql security definer set search_path=public as $$ declare result jsonb;begin
 if not public.is_admin() then raise exception 'Admin required' using errcode='42501';end if;
 select coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) into result from (
 select r.id,r.order_id,r.display_name,coalesce(o.plan_name,pl.name,'Paket') as plan_name,coalesce(p.display_name,'Teman CeritaKita') as name,coalesce(u.email,'Akun dihapus') as email,r.rating,r.title,r.body,r.status,r.is_featured,r.admin_note,
 (select count(*) from public.reports x where x.target_type='review' and x.target_id=r.id) as report_count,
 (select count(*) from public.reports x where x.target_type='review' and x.target_id=r.id and x.status='open') as open_reports
 from public.reviews r left join public.orders o on o.id=r.order_id left join public.plans pl on pl.id=r.plan_id left join public.profiles p on p.id=r.user_id left join auth.users u on u.id=r.user_id order by r.created_at desc,r.id desc
 )t;return result;
end; $$;

create or replace function public.admin_moderate_review(target_id uuid,operation text,reason text,note text,featured boolean)
returns void language plpgsql security definer set search_path=public as $$ declare previous record;reason_label text;begin
 if not public.is_admin() then raise exception 'Admin required' using errcode='42501';end if;
 if operation is null or operation not in ('hidden','removed','restore','feature','note') or note is null or char_length(note)>1000 or featured is null then raise exception 'Invalid action';end if;
 if operation in ('hidden','removed') and (reason is null or reason not in ('spam','sara','lainnya') or char_length(btrim(note))<3) then raise exception 'Reason required';end if;
 select id,status,is_featured,admin_note,order_id,user_id into previous from public.reviews where id=target_id for update;
 if previous.id is null then raise exception 'Review missing';end if;
 if operation='removed' then
 delete from public.reviews where id=target_id;
 elsif operation='hidden' then
 reason_label:=case reason when 'spam' then 'Spam' when 'sara' then 'SARA' else 'Lainnya' end;
 update public.reviews set status=operation,is_featured=false,admin_note=reason_label||': '||btrim(note) where id=target_id;
 elsif operation='restore' then
 if not exists(select 1 from public.orders o join public.reviews r on r.order_id=o.id where r.id=target_id and o.user_id=r.user_id and o.status='paid' and o.base_amount>0 and o.plan_id=r.plan_id) then raise exception 'Paid purchase required';end if;
 update public.reviews set status='approved',admin_note=null where id=target_id;
 elsif operation='feature' then
 if previous.status is distinct from 'approved' then raise exception 'Only approved reviews can be featured';end if;
 update public.reviews set is_featured=featured where id=target_id;
 else
 if previous.status in ('hidden','removed') and char_length(btrim(note))<3 then raise exception 'Keep the takedown reason';end if;
 update public.reviews set admin_note=nullif(btrim(note),'') where id=target_id;
 end if;
 if operation in ('hidden','removed','restore') then update public.reports set status='handled',handled_by=auth.uid(),handled_at=now() where target_type='review' and reports.target_id=admin_moderate_review.target_id and status='open';end if;
 perform public.record_admin_audit('moderation.review.'||operation,target_id::text,jsonb_build_object('before',to_jsonb(previous),'reason',reason,'note',note,'featured',featured));
end; $$;


revoke all on function public.admin_save_plan(jsonb),public.admin_review_list(),public.admin_moderate_review(uuid,text,text,text,boolean) from public,anon;
grant execute on function public.admin_save_plan(jsonb),public.admin_review_list(),public.admin_moderate_review(uuid,text,text,text,boolean) to authenticated;
commit;
