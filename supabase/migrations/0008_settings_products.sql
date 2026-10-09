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
